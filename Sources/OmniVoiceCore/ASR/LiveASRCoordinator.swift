import Foundation

@MainActor
final class LiveASRCoordinator {
    enum GateState: Equatable, Sendable {
        case notStarted
        case running
        case sawText(characterCount: Int)
        case startFailed(errorKind: String)
        case bufferOverflowed

        var diagnosticValue: String {
            switch self {
            case .notStarted:
                return "not_started"
            case .running:
                return "running"
            case .sawText:
                return "saw_text"
            case .startFailed:
                return "start_failed"
            case .bufferOverflowed:
                return "buffer_overflowed"
            }
        }

        var textCharacterCount: Int {
            guard case let .sawText(characterCount) = self else { return 0 }
            return characterCount
        }
    }

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
    private var transcriptAccumulator = LiveASRTranscriptAccumulator()
    private let bufferLimitSeconds: Double

    private(set) var previewText = ""
    private(set) var gateState: GateState = .notStarted

    init(bufferLimitSeconds: Double = 12) {
        self.bufferLimitSeconds = bufferLimitSeconds
    }

    func prepareForStart() {
        cancel()
        previewText = ""
        gateState = .notStarted
    }

    func beginPreparation(_ task: Task<Void, Never>) {
        preparationTask = task
        gateState = .running
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
        handleStartFailure(errorKind: "unknown")
    }

    func handleStartFailure(errorKind: String) {
        session = nil
        preparationTask = nil
        bufferedChunks.removeAll(keepingCapacity: true)
        bufferedSeconds = 0
        bufferOverflowed = true
        transcriptAccumulator.reset()
        previewText = ""
        gateState = .startFailed(errorKind: errorKind)
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
            transcriptAccumulator.reset()
            previewText = ""
            gateState = .bufferOverflowed
            return .bufferOverflowed(limitSeconds: bufferLimitSeconds)
        }
        return .buffered
    }

    func acceptPreview(
        _ update: LiveASRUpdate,
        isRecording: Bool,
        previewEnabled: Bool,
        now: Date = Date()
    ) -> String? {
        guard isRecording else { return nil }
        guard let snapshot = transcriptAccumulator.accept(update, now: now) else { return nil }
        let text = snapshot.displayText
        guard !text.isEmpty else { return nil }
        gateState = .sawText(characterCount: text.count)
        previewText = text
        guard previewEnabled else { return nil }
        return text
    }

    func makeFinalTask(useForSystemPipeline: Bool) -> Task<ASRRecognitionResult, Error>? {
        let task = preparationTask
        let overflowed = bufferOverflowed
        let transcriptSnapshot = transcriptAccumulator.snapshotForFinal()
        preparationTask = nil
        bufferedChunks.removeAll(keepingCapacity: true)
        bufferedSeconds = 0
        bufferOverflowed = false
        previewText = ""
        transcriptAccumulator.reset()
        gateState = .notStarted

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
            let result = try await session.finish()
            return LiveASRFinalTextResolver.resolve(
                sessionResult: result,
                snapshot: transcriptSnapshot
            )
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
        transcriptAccumulator.reset()
        gateState = .notStarted
    }

    private func takeSession() -> (any LiveSystemSpeechRecognitionSession)? {
        let current = session
        session = nil
        return current
    }
}
