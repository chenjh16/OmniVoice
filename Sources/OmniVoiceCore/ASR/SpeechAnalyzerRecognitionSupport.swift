import AVFoundation
import Foundation
import Speech

@available(macOS 26.0, *)
struct SpeechAnalyzerRuntime {
    let analyzer: SpeechAnalyzer
    let transcriber: SpeechTranscriber
    let audioFormat: AVAudioFormat?
}

@available(macOS 26.0, *)
enum SpeechAnalyzerRuntimePreparer {
    static func prepare(
        options: SystemSpeechRecognitionOptions,
        naturalAudioFormat: AVAudioFormat?
    ) async throws -> SpeechAnalyzerRuntime {
        guard SpeechTranscriber.isAvailable else {
            throw SystemSpeechRecognitionError.speechAnalyzerUnavailable
        }
        let requestedLocale = Locale(identifier: options.language.rawValue)
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw SystemSpeechRecognitionError.speechAnalyzerUnavailable
        }
        let transcriber = SpeechTranscriber(locale: supportedLocale, preset: .progressiveTranscription)
        let modules: [any SpeechModule] = [transcriber]
        try await ensureAssetsReady(for: modules)

        let analyzer = SpeechAnalyzer(modules: modules)
        let keywords = SystemASRKeywordPlanner.contextualStrings(from: options.keywordHints)
        if !keywords.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings[.general] = keywords
            try? await analyzer.setContext(context)
        }
        var compatibleFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules,
            considering: naturalAudioFormat
        )
        if compatibleFormat == nil {
            compatibleFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)
        }
        if compatibleFormat == nil {
            compatibleFormat = naturalAudioFormat
        }
        try await analyzer.prepareToAnalyze(in: compatibleFormat)
        return SpeechAnalyzerRuntime(
            analyzer: analyzer,
            transcriber: transcriber,
            audioFormat: compatibleFormat
        )
    }

    private static func ensureAssetsReady(for modules: [any SpeechModule]) async throws {
        let initialState = await assetState(for: modules)
        switch SpeechAnalyzerPreflightPlanner.action(for: initialState) {
        case .ready:
            return
        case .unavailable:
            throw SystemSpeechRecognitionError.speechAnalyzerUnavailable
        case .prepareAssets:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                try await request.downloadAndInstall()
            } else if initialState == .downloading {
                try await waitForAssetInstallation(modules: modules)
            } else {
                throw SystemSpeechRecognitionError.speechAnalyzerUnavailable
            }
        }

        let finalState = await assetState(for: modules)
        guard SpeechAnalyzerPreflightPlanner.action(for: finalState) == .ready else {
            throw SystemSpeechRecognitionError.speechAnalyzerUnavailable
        }
    }

    private static func waitForAssetInstallation(modules: [any SpeechModule]) async throws {
        for _ in 0..<12 {
            try await Task.sleep(nanoseconds: 500_000_000)
            if await assetState(for: modules) == .installed {
                return
            }
        }
    }

    private static func assetState(for modules: [any SpeechModule]) async -> SpeechAnalyzerAssetState {
        switch await AssetInventory.status(forModules: modules) {
        case .unsupported:
            return .unsupported
        case .supported:
            return .supported
        case .downloading:
            return .downloading
        case .installed:
            return .installed
        @unknown default:
            return .unsupported
        }
    }
}

@available(macOS 26.0, *)
final class SpeechAnalyzerAudioChunkConverter: @unchecked Sendable {
    private let targetFormat: AVAudioFormat?

    init(targetFormat: AVAudioFormat?) {
        self.targetFormat = targetFormat
    }

    func buffer(from chunk: AudioSampleChunk) -> AVAudioPCMBuffer? {
        guard let sourceBuffer = ClassicSpeechLiveRecognitionSession.buffer(from: chunk) else {
            return nil
        }
        guard let targetFormat else {
            return sourceBuffer
        }
        return AudioBufferConverter.convertSingleBuffer(sourceBuffer, to: targetFormat)
    }
}

@available(macOS 26.0, *)
final class SpeechAnalyzerLiveRecognitionSession: LiveSystemSpeechRecognitionSession, @unchecked Sendable {
    private let analyzer: SpeechAnalyzer
    private let transcriber: SpeechTranscriber
    private let converter: SpeechAnalyzerAudioChunkConverter
    private let continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
    private let streamStartTask: Task<Void, Error>
    private let collectorTask: Task<String, Error>
    private let lock = NSLock()
    private var cancelled = false

    init(
        options: SystemSpeechRecognitionOptions,
        onUpdate: @escaping @Sendable (LiveASRUpdate) -> Void
    ) async throws {
        let runtime = try await SpeechAnalyzerRuntimePreparer.prepare(
            options: options,
            naturalAudioFormat: nil
        )
        var streamContinuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation?
        let stream = AsyncThrowingStream<AnalyzerInput, Error> { continuation in
            streamContinuation = continuation
        }
        guard let continuation = streamContinuation else {
            throw SystemSpeechRecognitionError.recognitionFailed("Could not prepare live SpeechAnalyzer input")
        }

        self.analyzer = runtime.analyzer
        self.transcriber = runtime.transcriber
        self.converter = SpeechAnalyzerAudioChunkConverter(targetFormat: runtime.audioFormat)
        self.continuation = continuation
        self.streamStartTask = Task {
            try await runtime.analyzer.start(inputSequence: stream)
        }
        self.collectorTask = Task {
            var latest = ""
            for try await result in runtime.transcriber.results {
                latest = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                if !latest.isEmpty {
                    onUpdate(LiveASRUpdate(text: latest, isFinal: false))
                }
            }
            return latest
        }
    }

    func append(_ chunk: AudioSampleChunk) {
        guard let buffer = converter.buffer(from: chunk),
              !lock.withLock({ cancelled }) else {
            return
        }
        continuation.yield(AnalyzerInput(buffer: buffer))
    }

    func finish() async throws -> ASRRecognitionResult {
        continuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        try await streamStartTask.value
        let rawText = try await collectorTask.value
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw SystemSpeechRecognitionError.noTextRecognized }
        return ASRRecognitionResult(text: text, allowedAppleServerRecognition: false)
    }

    func cancel() {
        let shouldCancel = lock.withLock { () -> Bool in
            guard !cancelled else { return false }
            cancelled = true
            return true
        }
        guard shouldCancel else { return }
        continuation.finish(throwing: SystemSpeechRecognitionError.recognitionFailed("Live SpeechAnalyzer cancelled"))
        streamStartTask.cancel()
        collectorTask.cancel()
        Task {
            await analyzer.cancelAndFinishNow()
        }
    }
}
