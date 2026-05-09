import Foundation
import Testing
@testable import OmniVoiceCore

@Suite("System speech recognizer")
struct SystemSpeechRecognizerTests {
    @Test
    func customLanguageModelCacheKeyIsStableAndContentBased() {
        let first = SystemASRCustomLanguageModelCacheKey.version(
            localeIdentifier: "zh_CN",
            keywords: ["Swift", "  API  ", "macOS"]
        )
        let second = SystemASRCustomLanguageModelCacheKey.version(
            localeIdentifier: "zh_CN",
            keywords: ["macOS", "api", "swift"]
        )
        let differentLocale = SystemASRCustomLanguageModelCacheKey.version(
            localeIdentifier: "en_US",
            keywords: ["macOS", "api", "swift"]
        )
        let differentKeywords = SystemASRCustomLanguageModelCacheKey.version(
            localeIdentifier: "zh_CN",
            keywords: ["macOS", "api", "python"]
        )

        #expect(first == second)
        #expect(first != differentLocale)
        #expect(first != differentKeywords)
        #expect(first.count == 64)
        #expect(first.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil)
    }

    @Test
    func fileRecognitionTimeoutScalesWithAudioDuration() {
        #expect(SystemASRFileRecognitionTimeoutPlanner.timeoutSeconds(audioDurationSeconds: nil) == 20)
        #expect(SystemASRFileRecognitionTimeoutPlanner.timeoutSeconds(audioDurationSeconds: -1) == 20)
        #expect(SystemASRFileRecognitionTimeoutPlanner.timeoutSeconds(audioDurationSeconds: 2) == 20)
        #expect(SystemASRFileRecognitionTimeoutPlanner.timeoutSeconds(audioDurationSeconds: 20) == 38)
        #expect(SystemASRFileRecognitionTimeoutPlanner.timeoutSeconds(audioDurationSeconds: 300) == 180)
    }

    @Test
    func liveASREngineFallbackPlannerOnlyFallsBackFromSpeechAnalyzer() {
        #expect(LiveASREngineFallbackPlanner.engines(primary: .speechAnalyzer) == [
            .speechAnalyzer,
            .classicSpeech
        ])
        #expect(LiveASREngineFallbackPlanner.engines(primary: .classicSpeech) == [.classicSpeech])
        #expect(LiveASREngineFallbackPlanner.engines(primary: .appleOnlineSpeech) == [.appleOnlineSpeech])
    }

    @Test
    func systemSpeechRecognitionErrorsExposeSpecificDiagnosticKinds() {
        #expect(SystemSpeechRecognitionError.notAuthorized.diagnosticKind == "speech_not_authorized")
        #expect(SystemSpeechRecognitionError.recognizerUnavailable.diagnosticKind == "speech_recognizer_unavailable")
        #expect(SystemSpeechRecognitionError.speechAnalyzerUnavailable.diagnosticKind == "speech_analyzer_unavailable")
        #expect(SystemSpeechRecognitionError.onDeviceRecognitionUnavailable.diagnosticKind == "speech_on_device_unavailable")
        #expect(SystemSpeechRecognitionError.noTextRecognized.diagnosticKind == "speech_no_text")
        #expect(SystemSpeechRecognitionError.temporaryFileFailed.diagnosticKind == "speech_temp_file_failed")
        #expect(SystemSpeechRecognitionError.recognitionFailed("boom").diagnosticKind == "speech_recognition_failed")
    }

    @MainActor
    @Test
    func liveASRCoordinatorBuffersInstallsPreviewAndFinishes() async throws {
        let coordinator = LiveASRCoordinator(bufferLimitSeconds: 2)
        let chunk = AudioSampleChunk(samples: Array(repeating: 0.1, count: 1_600), sampleRate: 16_000)
        let session = FakeLiveASRSession(result: ASRRecognitionResult(text: "final draft"))

        coordinator.prepareForStart()
        coordinator.beginPreparation(Task {})
        #expect(coordinator.append(chunk, shouldRun: true) == .buffered)
        #expect(coordinator.install(session, isRecording: true) == .installed(bufferOverflowed: false))
        #expect(session.appendedChunkCount == 1)

        let preview = coordinator.acceptPreview(
            LiveASRUpdate(text: "  草稿 preview  ", isFinal: false),
            isRecording: true,
            previewEnabled: true
        )
        #expect(preview == "草稿 preview")
        #expect(coordinator.previewText == "草稿 preview")

        let finalTask = coordinator.makeFinalTask(useForSystemPipeline: true)
        let task = try #require(finalTask)
        let result = try await task.value
        #expect(result.text == "final draft")
        #expect(session.finishCount == 1)
    }

    @MainActor
    @Test
    func liveASRCoordinatorDropsOverflowedLiveFinalAndCancelsSession() {
        let coordinator = LiveASRCoordinator(bufferLimitSeconds: 0.01)
        let chunk = AudioSampleChunk(samples: Array(repeating: 0.1, count: 1_600), sampleRate: 16_000)
        let session = FakeLiveASRSession(result: ASRRecognitionResult(text: "unused"))

        coordinator.prepareForStart()
        coordinator.beginPreparation(Task {})
        #expect(coordinator.append(chunk, shouldRun: true) == .bufferOverflowed(limitSeconds: 0.01))
        #expect(coordinator.install(session, isRecording: true) == .installed(bufferOverflowed: true))
        #expect(coordinator.makeFinalTask(useForSystemPipeline: true) == nil)
        #expect(session.cancelCount == 1)
    }
}

private final class FakeLiveASRSession: LiveSystemSpeechRecognitionSession, @unchecked Sendable {
    private let result: ASRRecognitionResult
    private(set) var appendedChunkCount = 0
    private(set) var finishCount = 0
    private(set) var cancelCount = 0

    init(result: ASRRecognitionResult) {
        self.result = result
    }

    func append(_ chunk: AudioSampleChunk) {
        appendedChunkCount += 1
    }

    func finish() async throws -> ASRRecognitionResult {
        finishCount += 1
        return result
    }

    func cancel() {
        cancelCount += 1
    }
}
