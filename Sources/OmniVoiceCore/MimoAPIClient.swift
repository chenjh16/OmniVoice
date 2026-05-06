import Foundation

public enum MimoAPIError: LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case invalidWAV
    case invalidResponse
    case httpStatus(Int, String?)
    case authenticationFailed(String?)
    case modelDoesNotSupportAudio(String?)
    case malformedSSE(String?)
    case serverError(String)
    case streamEndedBeforeCompletion
    case noDeltaContent
    case emptyFinalText
    case networkFailure(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API Key missing"
        case .invalidWAV:
            return "Invalid WAV"
        case .invalidResponse:
            return "Invalid response"
        case .httpStatus(let status, let preview):
            return preview.map { "HTTP \(status): \($0)" } ?? "HTTP \(status)"
        case .authenticationFailed:
            return "Authentication failed"
        case .modelDoesNotSupportAudio:
            return "Model does not support audio"
        case .malformedSSE(let preview):
            return preview.map { "Malformed stream: \($0)" } ?? "Malformed stream"
        case .serverError(let message):
            return message
        case .streamEndedBeforeCompletion:
            return "Stream interrupted"
        case .noDeltaContent:
            return "No transcription delta"
        case .emptyFinalText:
            return "Empty transcription"
        case .networkFailure(let message):
            return message
        case .cancelled:
            return "Cancelled"
        }
    }

    public var diagnosticKind: String {
        switch self {
        case .missingAPIKey: return "missing_api_key"
        case .invalidWAV: return "invalid_wav"
        case .invalidResponse: return "invalid_response"
        case .httpStatus(let status, _): return "http_\(status)"
        case .authenticationFailed: return "authentication_failed"
        case .modelDoesNotSupportAudio: return "model_or_audio_unsupported"
        case .malformedSSE: return "malformed_sse"
        case .serverError: return "server_error"
        case .streamEndedBeforeCompletion: return "stream_ended_before_completion"
        case .noDeltaContent: return "no_delta_content"
        case .emptyFinalText: return "empty_final_text"
        case .networkFailure: return "network_failure"
        case .cancelled: return "cancelled"
        }
    }

    public var diagnosticPreview: String? {
        switch self {
        case .httpStatus(_, let preview), .authenticationFailed(let preview), .modelDoesNotSupportAudio(let preview), .malformedSSE(let preview):
            return preview
        case .serverError(let message), .networkFailure(let message):
            return message
        default:
            return nil
        }
    }

    public static func classifiedHTTP(status: Int, preview: String?) -> MimoAPIError {
        switch status {
        case 401, 403:
            return .authenticationFailed(preview)
        case 400, 404, 415, 422:
            return .modelDoesNotSupportAudio(preview)
        default:
            return .httpStatus(status, preview)
        }
    }
}

public struct TestConnectionResult: Equatable, Sendable {
    public let selectedModel: String
    public let modelsReachable: Bool
    public let selectedModelAllowed: Bool
    public let audioProbeAccepted: Bool?
    public let audioProbeError: String?
    public let message: String

    public init(
        selectedModel: String,
        modelsReachable: Bool,
        selectedModelAllowed: Bool,
        audioProbeAccepted: Bool?,
        audioProbeError: String? = nil,
        message: String
    ) {
        self.selectedModel = selectedModel
        self.modelsReachable = modelsReachable
        self.selectedModelAllowed = selectedModelAllowed
        self.audioProbeAccepted = audioProbeAccepted
        self.audioProbeError = audioProbeError
        self.message = message
    }
}

public struct SourceLatencyMeasurement: Equatable, Sendable {
    public let milliseconds: Int?
    public let httpStatus: Int?
    public let reachable: Bool
    public let allowedModelIDs: [String]
    public let measuredAt: Date
    public let errorKind: String?

    public init(
        milliseconds: Int?,
        httpStatus: Int?,
        reachable: Bool,
        allowedModelIDs: [String] = [],
        measuredAt: Date = Date(),
        errorKind: String? = nil
    ) {
        self.milliseconds = milliseconds
        self.httpStatus = httpStatus
        self.reachable = reachable
        self.allowedModelIDs = allowedModelIDs
        self.measuredAt = measuredAt
        self.errorKind = errorKind
    }

    public var allowedSpeechModels: [AllowedSpeechModel] {
        AllowedSpeechModel.filterSpeechModels(from: allowedModelIDs)
    }

    public var hasAllowedSpeechModel: Bool {
        !allowedSpeechModels.isEmpty
    }

    public var isAutoEligible: Bool {
        guard let httpStatus, (200..<300).contains(httpStatus) else { return false }
        return hasAllowedSpeechModel
    }
}

public enum AudioProbeSupport {
    public static func accepts(error: Error) -> Bool {
        guard let error = error as? MimoAPIError else { return false }
        switch error {
        case .noDeltaContent, .emptyFinalText:
            return true
        default:
            return false
        }
    }
}

public protocol TranscriptionClient: Sendable {
    func fetchModels() async throws -> [String]
    func measureModelsLatency(timeout: TimeInterval) async -> SourceLatencyMeasurement
    func testConnection(selectedModel: AllowedSpeechModel, runAudioProbe: Bool) async -> TestConnectionResult
    func transcribe(
        wavData: Data,
        model: AllowedSpeechModel,
        instruction: String,
        recordingSeconds: Double?,
        overallRMS: Float?,
        allowEmptyFinalText: Bool,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String
}

public final class MimoAPIClient: TranscriptionClient, @unchecked Sendable {
    private let config: MimoConfig
    private let session: URLSession
    private let onDiagnostic: (@Sendable (RuntimeDiagnostic) -> Void)?

    public init(
        config: MimoConfig,
        session: URLSession = .shared,
        onDiagnostic: (@Sendable (RuntimeDiagnostic) -> Void)? = nil
    ) {
        self.config = config
        self.session = session
        self.onDiagnostic = onDiagnostic
    }

    public func fetchModels() async throws -> [String] {
        var request = URLRequest(url: endpoint("/v1/models"))
        request.httpMethod = "GET"
        applyAuthorization(to: &request)

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response, preview: data.redactedPreview())
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data.map(\.id)
    }

    public func measureModelsLatency(timeout: TimeInterval = 6) async -> SourceLatencyMeasurement {
        let start = Date()
        do {
            var request = URLRequest(url: endpoint("/v1/models"))
            request.httpMethod = "GET"
            request.timeoutInterval = timeout
            applyAuthorization(to: &request)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw MimoAPIError.invalidResponse
            }
            let ids: [String]
            if (200..<300).contains(http.statusCode),
               let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data) {
                ids = decoded.data.map(\.id)
            } else {
                ids = []
            }
            return latencyMeasurement(start: start, statusCode: http.statusCode, allowedModelIDs: ids)
        } catch {
            let mapped = mapNetworkError(error)
            return SourceLatencyMeasurement(
                milliseconds: nil,
                httpStatus: nil,
                reachable: false,
                measuredAt: Date(),
                errorKind: mapped.diagnosticKind
            )
        }
    }

    public func testConnection(selectedModel: AllowedSpeechModel, runAudioProbe: Bool = false) async -> TestConnectionResult {
        do {
            let ids = try await fetchModels()
            let allowed = AllowedSpeechModel.filterSpeechModels(from: ids)
            let selectedAllowed = allowed.contains(selectedModel)

            var probeResult: Bool?
            if runAudioProbe, selectedAllowed {
                do {
                    try await probeAudioSupport(model: selectedModel)
                    probeResult = true
                } catch MimoAPIError.modelDoesNotSupportAudio {
                    probeResult = false
                } catch {
                    if AudioProbeSupport.accepts(error: error) {
                        probeResult = true
                    } else {
                        probeResult = false
                        let preview = sanitizedMessage(for: error)
                        return TestConnectionResult(
                            selectedModel: selectedModel.rawValue,
                            modelsReachable: true,
                            selectedModelAllowed: selectedAllowed,
                            audioProbeAccepted: false,
                            audioProbeError: preview,
                            message: "Models OK; \(selectedModel.rawValue) available; audio probe failed: \(preview)"
                        )
                    }
                }
            }

            let message: String
            if selectedAllowed {
                if probeResult == true {
                    message = "Models OK; \(selectedModel.rawValue) available; audio probe accepted"
                } else if probeResult == false {
                    message = "Models OK; \(selectedModel.rawValue) available; audio probe rejected"
                } else {
                    message = "Models OK; \(selectedModel.rawValue) available"
                }
            } else {
                message = "Models OK; \(selectedModel.rawValue) is not in allowed list"
            }
            return TestConnectionResult(
                selectedModel: selectedModel.rawValue,
                modelsReachable: true,
                selectedModelAllowed: selectedAllowed,
                audioProbeAccepted: probeResult,
                message: message
            )
        } catch {
            return TestConnectionResult(
                selectedModel: selectedModel.rawValue,
                modelsReachable: false,
                selectedModelAllowed: false,
                audioProbeAccepted: nil,
                message: sanitizedMessage(for: error)
            )
        }
    }

    public func probeAudioSupport(model: AllowedSpeechModel) async throws {
        let wav = Self.audioProbeWAV()
        _ = try await transcribe(
            wavData: wav,
            model: model,
            instruction: "This is an audio capability probe. If there is no clear speech, return an empty response. Do not explain.",
            recordingSeconds: 0.8,
            overallRMS: 0.02,
            allowEmptyFinalText: true,
            onDelta: { _ in }
        )
    }

    public static func audioProbeWAV() -> Data {
        let sampleRate = 16_000
        let count = Int(Double(sampleRate) * 0.8)
        let samples = (0..<count).map { index -> Float in
            let fadeLength = max(1, sampleRate / 20)
            let fadeIn = min(1, Float(index) / Float(fadeLength))
            let fadeOut = min(1, Float(count - index - 1) / Float(fadeLength))
            let envelope = min(fadeIn, fadeOut)
            return sin(Float(index) * 2 * .pi * 440 / Float(sampleRate)) * 0.025 * envelope
        }
        return WAVEncoder.encodePCM16WAV(samples: samples)
    }

    public func transcribe(
        wavData: Data,
        model: AllowedSpeechModel,
        instruction: String,
        recordingSeconds: Double? = nil,
        overallRMS: Float? = nil,
        allowEmptyFinalText: Bool = false,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard config.apiKey?.isEmpty == false else {
            emit(diagnostic(stage: "transcribe", model: model, recordingSeconds: recordingSeconds, wavData: wavData, rms: overallRMS, error: .missingAPIKey))
            throw MimoAPIError.missingAPIKey
        }
        guard WAVEncoder.validatePCM16Mono16kWAV(wavData) else {
            emit(diagnostic(stage: "transcribe", model: model, recordingSeconds: recordingSeconds, wavData: wavData, rms: overallRMS, error: .invalidWAV))
            throw MimoAPIError.invalidWAV
        }

        var request = URLRequest(url: endpoint("/v1/chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        applyAuthorization(to: &request)

        let payload = ChatCompletionRequest(
            model: model.rawValue,
            instruction: instruction,
            base64WAV: wavData.base64EncodedString()
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            let mapped = mapNetworkError(error)
            emit(diagnostic(stage: "transcribe", model: model, recordingSeconds: recordingSeconds, wavData: wavData, rms: overallRMS, error: mapped))
            throw mapped
        }

        let http = response as? HTTPURLResponse
        let contentType = http?.value(forHTTPHeaderField: "Content-Type")
        if let http, !(200..<300).contains(http.statusCode) {
            let preview = await readErrorPreview(from: bytes)
            let error = httpError(status: http.statusCode, preview: preview)
            emit(diagnostic(
                stage: "transcribe_http",
                model: model,
                recordingSeconds: recordingSeconds,
                wavData: wavData,
                rms: overallRMS,
                httpStatus: http.statusCode,
                contentType: contentType,
                error: error
            ))
            throw error
        }
        do {
            try validateHTTP(response, preview: nil)
        } catch let error as MimoAPIError {
            emit(diagnostic(stage: "transcribe_http", model: model, recordingSeconds: recordingSeconds, wavData: wavData, rms: overallRMS, contentType: contentType, error: error))
            throw error
        }

        var parser = ChatCompletionSSEParser()
        var finalText = ""
        var sawTerminalEvent = false
        var sseChunkCount = 0
        var deltaCharacterCount = 0
        var finishReason: String?

        do {
            for try await line in bytes.lines {
                if Task.isCancelled {
                    let error = MimoAPIError.cancelled
                    emit(diagnostic(stage: "transcribe_stream", model: model, recordingSeconds: recordingSeconds, wavData: wavData, rms: overallRMS, httpStatus: http?.statusCode, contentType: contentType, sseChunkCount: sseChunkCount, deltaCharacterCount: deltaCharacterCount, cancellationState: "task_cancelled", error: error))
                    throw error
                }
                if line.hasPrefix("data:") {
                    sseChunkCount += 1
                }
                let events = parser.feed(Data((line + "\n").utf8))
                for event in events {
                    switch event {
                    case .content(let text):
                        finalText += text
                        deltaCharacterCount += text.count
                        onDelta(text)
                    case .finished(let reason):
                        finishReason = reason
                        sawTerminalEvent = true
                    case .usageOnly:
                        continue
                    case .malformedJSON(let payload):
                        let error = MimoAPIError.malformedSSE(SecretRedactor.redact(String(payload.prefix(240))))
                        emit(diagnostic(stage: "transcribe_sse", model: model, recordingSeconds: recordingSeconds, wavData: wavData, rms: overallRMS, httpStatus: http?.statusCode, contentType: contentType, sseChunkCount: sseChunkCount, deltaCharacterCount: deltaCharacterCount, error: error))
                        throw error
                    case .serverError(let info):
                        let error = MimoAPIError.serverError(info.redactedDescription)
                        emit(diagnostic(stage: "transcribe_sse", model: model, recordingSeconds: recordingSeconds, wavData: wavData, rms: overallRMS, httpStatus: http?.statusCode, contentType: contentType, sseChunkCount: sseChunkCount, deltaCharacterCount: deltaCharacterCount, error: error))
                        throw error
                    }
                }
                if sawTerminalEvent {
                    let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !allowEmptyFinalText {
                        if deltaCharacterCount == 0 {
                            let error = MimoAPIError.noDeltaContent
                            emit(diagnostic(stage: "transcribe_complete", model: model, recordingSeconds: recordingSeconds, wavData: wavData, rms: overallRMS, httpStatus: http?.statusCode, contentType: contentType, sseChunkCount: sseChunkCount, deltaCharacterCount: deltaCharacterCount, finishReason: finishReason, error: error))
                            throw error
                        }
                        if trimmed.isEmpty {
                            let error = MimoAPIError.emptyFinalText
                            emit(diagnostic(stage: "transcribe_complete", model: model, recordingSeconds: recordingSeconds, wavData: wavData, rms: overallRMS, httpStatus: http?.statusCode, contentType: contentType, sseChunkCount: sseChunkCount, deltaCharacterCount: deltaCharacterCount, finishReason: finishReason, error: error))
                            throw error
                        }
                    }
                    emit(diagnostic(stage: "transcribe_complete", model: model, recordingSeconds: recordingSeconds, wavData: wavData, rms: overallRMS, httpStatus: http?.statusCode, contentType: contentType, sseChunkCount: sseChunkCount, deltaCharacterCount: deltaCharacterCount, finishReason: finishReason))
                    return trimmed
                }
            }
        } catch let error as MimoAPIError {
            throw error
        } catch {
            let mapped = mapNetworkError(error)
            emit(diagnostic(stage: "transcribe_stream", model: model, recordingSeconds: recordingSeconds, wavData: wavData, rms: overallRMS, httpStatus: http?.statusCode, contentType: contentType, sseChunkCount: sseChunkCount, deltaCharacterCount: deltaCharacterCount, error: mapped))
            throw mapped
        }

        for event in parser.finish() {
            switch event {
            case .content(let text):
                finalText += text
                deltaCharacterCount += text.count
                onDelta(text)
            case .finished(let reason):
                finishReason = reason
                sawTerminalEvent = true
            case .usageOnly:
                continue
            case .malformedJSON(let payload):
                let error = MimoAPIError.malformedSSE(SecretRedactor.redact(String(payload.prefix(240))))
                emit(diagnostic(stage: "transcribe_sse", model: model, recordingSeconds: recordingSeconds, wavData: wavData, rms: overallRMS, httpStatus: http?.statusCode, contentType: contentType, sseChunkCount: sseChunkCount, deltaCharacterCount: deltaCharacterCount, error: error))
                throw error
            case .serverError(let info):
                let error = MimoAPIError.serverError(info.redactedDescription)
                emit(diagnostic(stage: "transcribe_sse", model: model, recordingSeconds: recordingSeconds, wavData: wavData, rms: overallRMS, httpStatus: http?.statusCode, contentType: contentType, sseChunkCount: sseChunkCount, deltaCharacterCount: deltaCharacterCount, error: error))
                throw error
            }
        }

        guard sawTerminalEvent else {
            let error = MimoAPIError.streamEndedBeforeCompletion
            emit(diagnostic(stage: "transcribe_stream", model: model, recordingSeconds: recordingSeconds, wavData: wavData, rms: overallRMS, httpStatus: http?.statusCode, contentType: contentType, sseChunkCount: sseChunkCount, deltaCharacterCount: deltaCharacterCount, error: error))
            throw error
        }

        let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !allowEmptyFinalText {
            if deltaCharacterCount == 0 {
                let error = MimoAPIError.noDeltaContent
                emit(diagnostic(stage: "transcribe_complete", model: model, recordingSeconds: recordingSeconds, wavData: wavData, rms: overallRMS, httpStatus: http?.statusCode, contentType: contentType, sseChunkCount: sseChunkCount, deltaCharacterCount: deltaCharacterCount, finishReason: finishReason, error: error))
                throw error
            }
            if trimmed.isEmpty {
                let error = MimoAPIError.emptyFinalText
                emit(diagnostic(stage: "transcribe_complete", model: model, recordingSeconds: recordingSeconds, wavData: wavData, rms: overallRMS, httpStatus: http?.statusCode, contentType: contentType, sseChunkCount: sseChunkCount, deltaCharacterCount: deltaCharacterCount, finishReason: finishReason, error: error))
                throw error
            }
        }
        emit(diagnostic(stage: "transcribe_complete", model: model, recordingSeconds: recordingSeconds, wavData: wavData, rms: overallRMS, httpStatus: http?.statusCode, contentType: contentType, sseChunkCount: sseChunkCount, deltaCharacterCount: deltaCharacterCount, finishReason: finishReason))
        return trimmed
    }

    private func endpoint(_ path: String) -> URL {
        var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false)!
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, suffix].filter { !$0.isEmpty }.joined(separator: "/")
        return components.url!
    }

    private func latencyMeasurement(start: Date, statusCode: Int, allowedModelIDs: [String]) -> SourceLatencyMeasurement {
        SourceLatencyMeasurement(
            milliseconds: max(1, Int(Date().timeIntervalSince(start) * 1000)),
            httpStatus: statusCode,
            reachable: (200..<300).contains(statusCode),
            allowedModelIDs: allowedModelIDs,
            measuredAt: Date(),
            errorKind: (200..<300).contains(statusCode) ? nil : "http_\(statusCode)"
        )
    }

    private func applyAuthorization(to request: inout URLRequest) {
        guard let apiKey = config.apiKey, !apiKey.isEmpty else { return }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    private func validateHTTP(_ response: URLResponse, preview: String?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw MimoAPIError.invalidResponse
        }
        if !(200..<300).contains(http.statusCode) {
            throw httpError(status: http.statusCode, preview: preview)
        }
    }

    private func httpError(status: Int, preview: String?) -> MimoAPIError {
        MimoAPIError.classifiedHTTP(status: status, preview: preview)
    }

    private func sanitizedMessage(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return "Connection failed"
    }

    private func mapNetworkError(_ error: Error) -> MimoAPIError {
        if let urlError = error as? URLError {
            if urlError.code == .cancelled {
                return .cancelled
            }
            return .networkFailure("Network \(urlError.code.rawValue): \(urlError.localizedDescription)")
        }
        if let mimoError = error as? MimoAPIError {
            return mimoError
        }
        return .networkFailure("Network failed: \(error.localizedDescription)")
    }

    private func readErrorPreview(from bytes: URLSession.AsyncBytes, limit: Int = 800) async -> String? {
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

    private func diagnostic(
        stage: String,
        model: AllowedSpeechModel,
        recordingSeconds: Double? = nil,
        wavData: Data? = nil,
        rms: Float? = nil,
        httpStatus: Int? = nil,
        contentType: String? = nil,
        sseChunkCount: Int = 0,
        deltaCharacterCount: Int = 0,
        finishReason: String? = nil,
        cancellationState: String? = nil,
        error: MimoAPIError? = nil
    ) -> RuntimeDiagnostic {
        RuntimeDiagnostic(
            stage: stage,
            host: config.baseURL.host ?? config.baseURL.absoluteString,
            model: model.rawValue,
            recordingSeconds: recordingSeconds,
            wavBytes: wavData?.count,
            rms: rms,
            httpStatus: httpStatus,
            contentType: contentType,
            sseChunkCount: sseChunkCount,
            deltaCharacterCount: deltaCharacterCount,
            finishReason: finishReason,
            cancellationState: cancellationState,
            errorKind: error?.diagnosticKind,
            errorPreview: error?.diagnosticPreview
        )
    }

    private func emit(_ diagnostic: RuntimeDiagnostic) {
        RuntimeDiagnostic.log(diagnostic)
        onDiagnostic?(diagnostic)
    }
}

private extension Data {
    func redactedPreview(limit: Int = 800) -> String? {
        guard !isEmpty else { return nil }
        let previewData = prefix(limit)
        let text = String(data: previewData, encoding: .utf8) ?? previewData.base64EncodedString()
        return SecretRedactor.redact(text)
    }
}

private struct ChatCompletionRequest: Encodable {
    let model: String
    let stream = true
    let temperature = 0
    let thinking = Thinking(type: "disabled")
    let messages: [Message]

    init(model: String, instruction: String, base64WAV: String) {
        self.model = model
        self.messages = [
            Message(content: [
                .text(instruction),
                .inputAudio(data: base64WAV, format: "wav")
            ])
        ]
    }

    struct Thinking: Encodable {
        let type: String
    }

    struct Message: Encodable {
        let role = "user"
        let content: [ContentBlock]
    }

    enum ContentBlock: Encodable {
        case text(String)
        case inputAudio(data: String, format: String)

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case inputAudio = "input_audio"
        }

        enum AudioCodingKeys: String, CodingKey {
            case data
            case format
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .inputAudio(let data, let format):
                try container.encode("input_audio", forKey: .type)
                var audio = container.nestedContainer(keyedBy: AudioCodingKeys.self, forKey: .inputAudio)
                try audio.encode(data, forKey: .data)
                try audio.encode(format, forKey: .format)
            }
        }
    }
}
