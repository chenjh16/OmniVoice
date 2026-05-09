import Foundation

@MainActor
final class LiveASRCoordinator {
    enum InstallResult: Equatable {
        case installed(bufferOverflowed: Bool)
        case cancelledBecauseNotRecording
    }

    enum AppendResult: Equatable {
        case ignored
        case appendedToSession
        case buffered
        case bufferOverflowed(limitSeconds: Double)
    }

    private var session: (any LiveSystemSpeechRecognitionSession)?
    private var preparationTask: Task<Void, Never>?
    private var bufferedChunks: [AudioSampleChunk] = []
    private var bufferedSeconds: Double = 0
    private var bufferOverflowed = false
    private let bufferLimitSeconds: Double

    private(set) var previewText = ""

    init(bufferLimitSeconds: Double = 12) {
        self.bufferLimitSeconds = bufferLimitSeconds
    }

    func prepareForStart() {
        cancel()
        previewText = ""
    }

    func beginPreparation(_ task: Task<Void, Never>) {
        preparationTask = task
    }

    func install(
        _ newSession: any LiveSystemSpeechRecognitionSession,
        isRecording: Bool
    ) -> InstallResult {
        guard isRecording else {
            newSession.cancel()
            return .cancelledBecauseNotRecording
        }

        session = newSession
        for chunk in bufferedChunks {
            newSession.append(chunk)
        }
        bufferedChunks.removeAll(keepingCapacity: true)
        bufferedSeconds = 0
        return .installed(bufferOverflowed: bufferOverflowed)
    }

    func handleStartFailure() {
        session = nil
        preparationTask = nil
        bufferedChunks.removeAll(keepingCapacity: true)
        bufferedSeconds = 0
        bufferOverflowed = true
    }

    func append(_ chunk: AudioSampleChunk, shouldRun: Bool) -> AppendResult {
        guard shouldRun else { return .ignored }

        if let session {
            session.append(chunk)
            return .appendedToSession
        }

        guard preparationTask != nil, !bufferOverflowed else { return .ignored }
        bufferedChunks.append(chunk)
        bufferedSeconds += Double(chunk.samples.count) / max(chunk.sampleRate, 1)
        if bufferedSeconds > bufferLimitSeconds {
            bufferedChunks.removeAll(keepingCapacity: true)
            bufferedSeconds = 0
            bufferOverflowed = true
            return .bufferOverflowed(limitSeconds: bufferLimitSeconds)
        }
        return .buffered
    }

    func acceptPreview(
        _ update: LiveASRUpdate,
        isRecording: Bool,
        previewEnabled: Bool
    ) -> String? {
        guard isRecording, previewEnabled else { return nil }
        let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        previewText = text
        return text
    }

    func makeFinalTask(useForSystemPipeline: Bool) -> Task<ASRRecognitionResult, Error>? {
        let task = preparationTask
        let overflowed = bufferOverflowed
        preparationTask = nil
        bufferedChunks.removeAll(keepingCapacity: true)
        bufferedSeconds = 0
        bufferOverflowed = false
        previewText = ""

        guard useForSystemPipeline, !overflowed else {
            task?.cancel()
            cancel()
            return nil
        }

        return Task { [weak self] in
            if let task {
                await task.value
            }
            guard let session = await MainActor.run(body: { self?.takeSession() }) else {
                throw SystemSpeechRecognitionError.recognitionFailed("Live ASR did not start")
            }
            return try await session.finish()
        }
    }

    func cancel() {
        preparationTask?.cancel()
        preparationTask = nil
        session?.cancel()
        session = nil
        bufferedChunks.removeAll(keepingCapacity: true)
        bufferedSeconds = 0
        bufferOverflowed = false
        previewText = ""
    }

    private func takeSession() -> (any LiveSystemSpeechRecognitionSession)? {
        let current = session
        session = nil
        return current
    }
}
