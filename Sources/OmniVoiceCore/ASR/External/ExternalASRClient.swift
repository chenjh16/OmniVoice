import AVFoundation
import Foundation

public final class ExternalASRClient: @unchecked Sendable {
    private let plugin: ExternalASRPlugin

    public init(plugin: ExternalASRPlugin) {
        self.plugin = plugin
    }

    public func recognize(chunks: [AudioSampleChunk]) async throws -> ASRRecognitionResult {
        let (connection, iterator) = try await startConnection(streaming: false)
        var responseIterator = iterator
        defer { connection.close() }

        for chunk in chunks {
            let pcm16 = try ExternalASRAudioConverter.pcm16Data(from: chunk)
            try connection.send(try ExternalASRProtocol.audioRequest(pcm16: pcm16))
        }
        try connection.send(try ExternalASRProtocol.finishRequest())

        while let response = try await responseIterator.next() {
            switch response {
            case .ready, .partial:
                continue
            case .final(let text):
                return ASRRecognitionResult(text: text)
            case .error(let message):
                throw SystemSpeechRecognitionError.recognitionFailed(message)
            }
        }
        throw SystemSpeechRecognitionError.recognitionFailed("External ASR helper ended before final response")
    }

    public func makeLiveSession(
        onUpdate: @escaping @Sendable (LiveASRUpdate) -> Void
    ) async throws -> ExternalASRLiveRecognitionSession {
        let (connection, iterator) = try await startConnection(streaming: true)
        return ExternalASRLiveRecognitionSession(
            connection: connection,
            responseIterator: iterator,
            onUpdate: onUpdate
        )
    }

    private func startConnection(
        streaming: Bool
    ) async throws -> (
        ExternalASRProcessConnection,
        AsyncThrowingStream<ExternalASRResponse, Error>.Iterator
    ) {
        let connection = try ExternalASRProcessConnection(plugin: plugin)
        var iterator = connection.responses.makeAsyncIterator()
        try connection.send(try ExternalASRProtocol.startRequest(streaming: streaming))

        while let response = try await iterator.next() {
            switch response {
            case .ready:
                return (connection, iterator)
            case .error(let message):
                connection.close()
                throw SystemSpeechRecognitionError.recognitionFailed(message)
            case .partial, .final:
                continue
            }
        }
        connection.close()
        throw SystemSpeechRecognitionError.recognitionFailed("External ASR helper ended before ready response")
    }
}

final class ExternalASRProcessConnection: @unchecked Sendable {
    let responses: AsyncThrowingStream<ExternalASRResponse, Error>

    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let responseContinuation: AsyncThrowingStream<ExternalASRResponse, Error>.Continuation
    private let readerQueue = DispatchQueue(label: "omnivoice.external-asr.stdout")

    init(plugin: ExternalASRPlugin) throws {
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        var continuation: AsyncThrowingStream<ExternalASRResponse, Error>.Continuation!
        responses = AsyncThrowingStream { streamContinuation in
            continuation = streamContinuation
        }
        responseContinuation = continuation

        process = Process()
        process.executableURL = plugin.executableURL
        process.currentDirectoryURL = plugin.pluginDirectoryURL
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        input = inputPipe.fileHandleForWriting
        output = outputPipe.fileHandleForReading

        try process.run()
        startReader()
    }

    func send(_ data: Data) throws {
        var line = data
        line.append(0x0A)
        try input.write(contentsOf: line)
    }

    func close() {
        try? input.close()
        if process.isRunning {
            process.terminate()
        }
    }

    private func startReader() {
        let output = output
        let continuation = responseContinuation
        readerQueue.async {
            var buffer = Data()
            do {
                while true {
                    let chunk = output.availableData
                    if chunk.isEmpty { break }
                    buffer.append(chunk)
                    try Self.drainCompleteLines(from: &buffer, continuation: continuation)
                }
                if !buffer.isEmpty {
                    try Self.emit(buffer, continuation: continuation)
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    private static func drainCompleteLines(
        from buffer: inout Data,
        continuation: AsyncThrowingStream<ExternalASRResponse, Error>.Continuation
    ) throws {
        let newline = Data([0x0A])
        while let range = buffer.firstRange(of: newline) {
            let line = buffer[..<range.lowerBound]
            buffer.removeSubrange(...range.lowerBound)
            try emit(Data(line), continuation: continuation)
        }
    }

    private static func emit(
        _ data: Data,
        continuation: AsyncThrowingStream<ExternalASRResponse, Error>.Continuation
    ) throws {
        guard let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !line.isEmpty else {
            return
        }
        continuation.yield(try ExternalASRProtocol.response(fromLine: line))
    }
}

enum ExternalASRAudioConverter {
    static func pcm16Data(from chunk: AudioSampleChunk) throws -> Data {
        let samples = try samples16k(from: chunk)
        var data = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            let scaled = clamped < 0 ? clamped * 32768 : clamped * 32767
            var value = Int16(scaled).littleEndian
            withUnsafeBytes(of: &value) { bytes in
                data.append(contentsOf: bytes)
            }
        }
        return data
    }

    private static func samples16k(from chunk: AudioSampleChunk) throws -> [Float] {
        guard abs(chunk.sampleRate - 16_000) > 0.5 else { return chunk.samples }
        guard let source = AudioBufferConverter.monoFloatBuffer(samples: chunk.samples, sampleRate: chunk.sampleRate),
              let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
              ),
              let converted = AudioBufferConverter.convertSingleBuffer(source, to: targetFormat),
              let data = converted.floatChannelData?[0] else {
            throw SystemSpeechRecognitionError.recognitionFailed("Could not resample audio for external ASR")
        }
        return (0..<Int(converted.frameLength)).map { data[$0] }
    }
}
