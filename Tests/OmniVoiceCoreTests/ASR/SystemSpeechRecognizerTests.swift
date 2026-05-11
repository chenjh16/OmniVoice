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
    func systemASRRuntimeRecoveryPrefersClassicDuringCooldown() {
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(SystemASRRuntimeRecoveryPlanner.preferredLiveEngine(
            configured: .speechAnalyzer,
            now: now,
            speechAnalyzerCooldownUntil: now.addingTimeInterval(10)
        ) == .classicSpeech)
        #expect(SystemASRRuntimeRecoveryPlanner.preferredLiveEngine(
            configured: .speechAnalyzer,
            now: now,
            speechAnalyzerCooldownUntil: now.addingTimeInterval(-1)
        ) == .speechAnalyzer)
        #expect(SystemASRRuntimeRecoveryPlanner.preferredLiveEngine(
            configured: .classicSpeech,
            now: now,
            speechAnalyzerCooldownUntil: now.addingTimeInterval(10)
        ) == .classicSpeech)
        #expect(SystemASRRuntimeRecoveryPlanner.preferredLiveEngine(
            configured: .appleOnlineSpeech,
            now: now,
            speechAnalyzerCooldownUntil: now.addingTimeInterval(10)
        ) == .appleOnlineSpeech)
    }

    @Test
    func systemASRRuntimeRecoveryCooldownAndProbeRulesAreExplicit() {
        let now = Date(timeIntervalSince1970: 2_000)
        #expect(SystemASRRuntimeRecoveryPlanner.cooldownUntil(event: .didWake, now: now) == now.addingTimeInterval(
            SystemASRRuntimeRecoveryPlanner.wakeCooldownSeconds
        ))
        #expect(SystemASRRuntimeRecoveryPlanner.cooldownUntil(event: .screenUnlocked, now: now) == now.addingTimeInterval(
            SystemASRRuntimeRecoveryPlanner.wakeCooldownSeconds
        ))
        #expect(SystemASRRuntimeRecoveryPlanner.cooldownUntil(event: .speechAnalyzerStartFailed, now: now) == now.addingTimeInterval(
            SystemASRRuntimeRecoveryPlanner.failedStartCooldownSeconds
        ))
        #expect(SystemASRRuntimeRecoveryPlanner.cooldownUntil(event: .willSleep, now: now) == nil)
        #expect(SystemASRRuntimeRecoveryPlanner.shouldScheduleSpeechAnalyzerProbe(
            configured: .speechAnalyzer,
            speechAnalyzerAvailable: true
        ))
        #expect(!SystemASRRuntimeRecoveryPlanner.shouldScheduleSpeechAnalyzerProbe(
            configured: .speechAnalyzer,
            speechAnalyzerAvailable: false
        ))
        #expect(!SystemASRRuntimeRecoveryPlanner.shouldScheduleSpeechAnalyzerProbe(
            configured: .classicSpeech,
            speechAnalyzerAvailable: true
        ))
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
        let session = FakeLiveASRSession(result: ASRRecognitionResult(text: "草稿 preview"))
        let start = Date(timeIntervalSince1970: 100)

        coordinator.prepareForStart()
        #expect(coordinator.gateState == .notStarted)
        coordinator.beginPreparation(Task {})
        #expect(coordinator.gateState == .running)
        #expect(coordinator.append(chunk, shouldRun: true) == .buffered)
        #expect(coordinator.install(session, isRecording: true) == .installed(bufferOverflowed: false))
        #expect(session.appendedChunkCount == 1)

        let hiddenPreview = coordinator.acceptPreview(
            LiveASRUpdate(text: "  hidden evidence  ", isFinal: false),
            isRecording: true,
            previewEnabled: false,
            now: start
        )
        #expect(hiddenPreview == nil)
        #expect(coordinator.previewText == "hidden evidence")
        #expect(coordinator.gateState == .sawText(characterCount: 15))

        let preview = coordinator.acceptPreview(
            LiveASRUpdate(text: "  草稿 preview  ", isFinal: false),
            isRecording: true,
            previewEnabled: true,
            now: start.addingTimeInterval(0.2)
        )
        #expect(preview == "hidden evidence 草稿 preview")
        #expect(coordinator.previewText == "hidden evidence 草稿 preview")
        #expect(coordinator.gateState == .sawText(characterCount: 26))

        let finalTask = coordinator.makeFinalTask(useForSystemPipeline: true)
        let task = try #require(finalTask)
        let result = try await task.value
        #expect(result.text == "hidden evidence 草稿 preview")
        #expect(session.finishCount == 1)
        #expect(coordinator.gateState == .notStarted)
    }

    @MainActor
    @Test
    func liveASRCoordinatorAccumulatesPreviewTextAcrossSegments() async throws {
        let coordinator = LiveASRCoordinator(bufferLimitSeconds: 2)
        let session = FakeLiveASRSession(result: ASRRecognitionResult(text: "第二段内容"))
        let start = Date(timeIntervalSince1970: 200)

        coordinator.prepareForStart()
        coordinator.beginPreparation(Task {})
        #expect(coordinator.install(session, isRecording: true) == .installed(bufferOverflowed: false))

        let first = coordinator.acceptPreview(
            LiveASRUpdate(text: "第一段内容", isFinal: false),
            isRecording: true,
            previewEnabled: true,
            now: start
        )
        #expect(first == "第一段内容")

        let second = coordinator.acceptPreview(
            LiveASRUpdate(text: "第二段内容", isFinal: false),
            isRecording: true,
            previewEnabled: true,
            now: start.addingTimeInterval(1.5)
        )
        #expect(second == "第一段内容第二段内容")
        #expect(coordinator.previewText == "第一段内容第二段内容")

        let finalTask = try #require(coordinator.makeFinalTask(useForSystemPipeline: true))
        let result = try await finalTask.value
        #expect(result.text == "第一段内容第二段内容")
    }

    @MainActor
    @Test
    func liveASRCoordinatorAccumulatesPreviewTextAcrossShortReset() async throws {
        let coordinator = LiveASRCoordinator(bufferLimitSeconds: 2)
        let session = FakeLiveASRSession(result: ASRRecognitionResult(text: "第二段内容"))
        let start = Date(timeIntervalSince1970: 250)

        coordinator.prepareForStart()
        coordinator.beginPreparation(Task {})
        #expect(coordinator.install(session, isRecording: true) == .installed(bufferOverflowed: false))

        let first = coordinator.acceptPreview(
            LiveASRUpdate(text: "第一段内容", isFinal: false),
            isRecording: true,
            previewEnabled: true,
            now: start
        )
        let second = coordinator.acceptPreview(
            LiveASRUpdate(text: "第二段内容", isFinal: false),
            isRecording: true,
            previewEnabled: true,
            now: start.addingTimeInterval(0.2)
        )

        #expect(first == "第一段内容")
        #expect(second == "第一段内容第二段内容")
        #expect(coordinator.previewText == "第一段内容第二段内容")

        let finalTask = try #require(coordinator.makeFinalTask(useForSystemPipeline: true))
        let result = try await finalTask.value
        #expect(result.text == "第一段内容第二段内容")
    }

    @MainActor
    @Test
    func liveASRCoordinatorAccumulatesWhenPreviewIsDisabled() async throws {
        let coordinator = LiveASRCoordinator(bufferLimitSeconds: 2)
        let session = FakeLiveASRSession(result: ASRRecognitionResult(text: "second segment"))
        let start = Date(timeIntervalSince1970: 300)

        coordinator.prepareForStart()
        coordinator.beginPreparation(Task {})
        #expect(coordinator.install(session, isRecording: true) == .installed(bufferOverflowed: false))

        let first = coordinator.acceptPreview(
            LiveASRUpdate(text: "first segment", isFinal: false),
            isRecording: true,
            previewEnabled: false,
            now: start
        )
        let second = coordinator.acceptPreview(
            LiveASRUpdate(text: "second segment", isFinal: false),
            isRecording: true,
            previewEnabled: false,
            now: start.addingTimeInterval(0.2)
        )

        #expect(first == nil)
        #expect(second == nil)
        #expect(coordinator.previewText == "first segment second segment")

        let finalTask = try #require(coordinator.makeFinalTask(useForSystemPipeline: true))
        let result = try await finalTask.value
        #expect(result.text == "first segment second segment")
    }

    @MainActor
    @Test
    func liveASRCoordinatorDropsOverflowedLiveFinalAndCancelsSession() {
        let coordinator = LiveASRCoordinator(bufferLimitSeconds: 0.01)
        let chunk = AudioSampleChunk(samples: Array(repeating: 0.1, count: 1_600), sampleRate: 16_000)
        let session = FakeLiveASRSession(result: ASRRecognitionResult(text: "unused"))

        coordinator.prepareForStart()
        coordinator.beginPreparation(Task {})
        _ = coordinator.acceptPreview(
            LiveASRUpdate(text: "stale preview", isFinal: false),
            isRecording: true,
            previewEnabled: true
        )
        #expect(coordinator.append(chunk, shouldRun: true) == .bufferOverflowed(limitSeconds: 0.01))
        #expect(coordinator.gateState == .bufferOverflowed)
        #expect(coordinator.previewText == "")
        #expect(coordinator.install(session, isRecording: true) == .installed(bufferOverflowed: true))
        #expect(coordinator.makeFinalTask(useForSystemPipeline: true) == nil)
        #expect(session.cancelCount == 1)
        #expect(coordinator.gateState == .notStarted)
    }

    @MainActor
    @Test
    func liveASRCoordinatorExposesStartFailureForQualityGate() {
        let coordinator = LiveASRCoordinator()
        coordinator.prepareForStart()
        coordinator.beginPreparation(Task {})
        coordinator.handleStartFailure(errorKind: "speech_not_authorized")
        #expect(coordinator.gateState == .startFailed(errorKind: "speech_not_authorized"))
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
