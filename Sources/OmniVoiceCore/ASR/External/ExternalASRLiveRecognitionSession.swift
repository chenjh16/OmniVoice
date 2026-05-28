import Foundation

public final class ExternalASRLiveRecognitionSession: LiveSystemSpeechRecognitionSession, @unchecked Sendable {
    private let connection: ExternalASRProcessConnection
    private let responseTask: Task<ASRRecognitionResult, Error>
    private let lock = NSLock()
    private var appendError: Error?
    private var didFinish = false

    init(
        connection: ExternalASRProcessConnection,
        responseIterator: AsyncThrowingStream<ExternalASRResponse, Error>.Iterator,
        onUpdate: @escaping @Sendable (LiveASRUpdate) -> Void
    ) {
        self.connection = connection
        var iterator = responseIterator
        responseTask = Task {
            while let response = try await iterator.next() {
                switch response {
                case .ready:
                    continue
                case .partial(let text, let replace):
                    onUpdate(LiveASRUpdate(
                        text: text,
                        isFinal: false,
                        replacesCurrentSegment: replace
                    ))
                case .final(let text):
                    onUpdate(LiveASRUpdate(
                        text: text,
                        isFinal: true,
                        replacesCurrentSegment: true
                    ))
                    return ASRRecognitionResult(text: text)
                case .error(let message):
                    throw SystemSpeechRecognitionError.recognitionFailed(message)
                }
            }
            throw SystemSpeechRecognitionError.recognitionFailed("External ASR helper ended before final response")
        }
    }

    public func append(_ chunk: AudioSampleChunk) {
        do {
            let pcm16 = try ExternalASRAudioConverter.pcm16Data(from: chunk)
            try connection.send(try ExternalASRProtocol.audioRequest(pcm16: pcm16))
        } catch {
            lock.withLock {
                appendError = error
            }
            connection.close()
        }
    }

    public func finish() async throws -> ASRRecognitionResult {
        try lock.withLock {
            if didFinish {
                throw SystemSpeechRecognitionError.recognitionFailed("External ASR live session already finished")
            }
            didFinish = true
            if let appendError {
                throw appendError
            }
        }
        defer { connection.close() }
        try connection.send(try ExternalASRProtocol.finishRequest())
        return try await responseTask.value
    }

    public func cancel() {
        responseTask.cancel()
        connection.close()
    }
}
