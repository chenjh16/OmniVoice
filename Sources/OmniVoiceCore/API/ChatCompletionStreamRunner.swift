import Foundation

struct ChatCompletionStreamStages {
    let initial: String
    let http: String
    let stream: String
    let sse: String
    let complete: String

    static let transcription = ChatCompletionStreamStages(
        initial: "transcribe",
        http: "transcribe_http",
        stream: "transcribe_stream",
        sse: "transcribe_sse",
        complete: "transcribe_complete"
    )

    static let textCompletion = ChatCompletionStreamStages(
        initial: "text_completion",
        http: "text_completion_http",
        stream: "text_completion_stream",
        sse: "text_completion_sse",
        complete: "text_completion_complete"
    )
}

struct ChatCompletionStreamRunner {
    let session: URLSession
    let request: URLRequest
    let allowEmptyFinalText: Bool
    let stages: ChatCompletionStreamStages
    let classifyHTTPError: (Int, String?) -> MimoAPIError
    let classifyServerError: (String) -> MimoAPIError
    let mapNetworkError: (Error) -> MimoAPIError
    let makeDiagnostic: (String, Int?, String?, Int, Int, String?, String?, MimoAPIError?) -> RuntimeDiagnostic
    let emit: (RuntimeDiagnostic) -> Void
    let onDelta: @Sendable (String) -> Void

    func run() async throws -> String {
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            let mapped = mapNetworkError(error)
            emit(makeDiagnostic(stages.initial, nil, nil, 0, 0, nil, nil, mapped))
            throw mapped
        }

        guard let http = response as? HTTPURLResponse else {
            let error = MimoAPIError.invalidResponse
            emit(makeDiagnostic(stages.http, nil, nil, 0, 0, nil, nil, error))
            throw error
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type")
        guard (200..<300).contains(http.statusCode) else {
            let preview = await Self.readErrorPreview(from: bytes)
            let error = classifyHTTPError(http.statusCode, preview)
            emit(makeDiagnostic(stages.http, http.statusCode, contentType, 0, 0, nil, nil, error))
            throw error
        }

        var parser = ChatCompletionSSEParser()
        var finalText = ""
        var sawTerminalEvent = false
        var sseChunkCount = 0
        var deltaCharacterCount = 0
        var finishReason: String?

        func handle(_ event: SSEStreamEvent) throws {
            switch event {
            case .content(let text):
                finalText += text
                deltaCharacterCount += text.count
                onDelta(text)
            case .finished(let reason):
                finishReason = reason
                sawTerminalEvent = true
            case .usageOnly:
                return
            case .malformedJSON(let payload):
                let error = MimoAPIError.malformedSSE(SecretRedactor.redact(String(payload.prefix(240))))
                emit(makeDiagnostic(stages.sse, http.statusCode, contentType, sseChunkCount, deltaCharacterCount, nil, nil, error))
                throw error
            case .serverError(let info):
                let error = classifyServerError(info.redactedDescription)
                emit(makeDiagnostic(stages.sse, http.statusCode, contentType, sseChunkCount, deltaCharacterCount, nil, nil, error))
                throw error
            }
        }

        func completedTextIfReady() throws -> String? {
            guard sawTerminalEvent else { return nil }
            let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !allowEmptyFinalText {
                if deltaCharacterCount == 0 {
                    let error = MimoAPIError.noDeltaContent
                    emit(makeDiagnostic(stages.complete, http.statusCode, contentType, sseChunkCount, deltaCharacterCount, finishReason, nil, error))
                    throw error
                }
                if trimmed.isEmpty {
                    let error = MimoAPIError.emptyFinalText
                    emit(makeDiagnostic(stages.complete, http.statusCode, contentType, sseChunkCount, deltaCharacterCount, finishReason, nil, error))
                    throw error
                }
            }
            emit(makeDiagnostic(stages.complete, http.statusCode, contentType, sseChunkCount, deltaCharacterCount, finishReason, nil, nil))
            return trimmed
        }

        do {
            for try await line in bytes.lines {
                if Task.isCancelled {
                    let error = MimoAPIError.cancelled
                    emit(makeDiagnostic(stages.stream, http.statusCode, contentType, sseChunkCount, deltaCharacterCount, nil, "task_cancelled", error))
                    throw error
                }
                if line.hasPrefix("data:") {
                    sseChunkCount += 1
                }
                for event in parser.feed(Data((line + "\n").utf8)) {
                    try handle(event)
                }
                if let completed = try completedTextIfReady() {
                    return completed
                }
            }
        } catch let error as MimoAPIError {
            throw error
        } catch {
            let mapped = mapNetworkError(error)
            emit(makeDiagnostic(stages.stream, http.statusCode, contentType, sseChunkCount, deltaCharacterCount, nil, nil, mapped))
            throw mapped
        }

        for event in parser.finish() {
            try handle(event)
        }
        if let completed = try completedTextIfReady() {
            return completed
        }

        let error = MimoAPIError.streamEndedBeforeCompletion
        emit(makeDiagnostic(stages.stream, http.statusCode, contentType, sseChunkCount, deltaCharacterCount, nil, nil, error))
        throw error
    }

    private static func readErrorPreview(from bytes: URLSession.AsyncBytes, limit: Int = 800) async -> String? {
        var data = Data()
        do {
            for try await byte in bytes {
                if data.count >= limit { break }
                data.append(byte)
            }
        } catch {
            return "Failed to read error body: \(error.localizedDescription)"
        }
        return data.redactedPreview(limit: limit)
    }
}
