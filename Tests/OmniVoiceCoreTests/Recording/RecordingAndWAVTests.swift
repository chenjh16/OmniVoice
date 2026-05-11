import Foundation
import ApplicationServices
import Testing
@testable import OmniVoiceCore

@Suite("Recording and WAV")
struct RecordingAndWAVTests {
    @Test
    func recordingValidatorRejectsShortAndQuietAudio() {
        #expect(RecordingValidator.validate(durationSeconds: 0.2, overallRMS: 0.5).status == .tooShort)
        #expect(RecordingValidator.validate(durationSeconds: 0.4, overallRMS: 0.5).status == .tooShort)
        #expect(RecordingValidator.validate(
            durationSeconds: 0.4,
            overallRMS: 0.5,
            minimumDurationSeconds: MinRecordingDuration.milliseconds300.seconds
        ).status == .valid)
        #expect(RecordingValidator.validate(durationSeconds: 1.0, overallRMS: 0.001).status == .tooQuiet)
        #expect(RecordingValidator.validate(durationSeconds: 1.0, overallRMS: 0.1).status == .valid)
        #expect(RecordingValidator.validate(
            durationSeconds: 1.0,
            overallRMS: 0.001,
            policy: .durationOnly
        ).status == .valid)
        #expect(RecordingValidator.validate(
            durationSeconds: 0.2,
            overallRMS: 0.001,
            policy: .durationOnly
        ).status == .tooShort)
        #expect(RecordingValidationPolicyResolver.policy(for: .inputAudio) == .voiceGated)
        #expect(RecordingValidationPolicyResolver.policy(for: .systemASRTextLLM) == .durationOnly)
        #expect(RecordingValidationPolicyResolver.policy(for: .systemASROnly) == .durationOnly)
        #expect(RecordingStopCancellationPlanner.shouldCancelRecordingSource(recordingStopInProgress: false))
        #expect(!RecordingStopCancellationPlanner.shouldCancelRecordingSource(recordingStopInProgress: true))
    }

    @Test
    func directAudioASRGateBlocksOnlyLowRMSNoTextDirectAudio() {
        #expect(DirectAudioASRGatePlanner.strongSpeechRMS == 0.018)
        #expect(DirectAudioASRGatePlanner.decision(
            mode: .inputAudio,
            gateState: .running,
            overallRMS: 0.005
        ) == .block(errorKind: "asr_gate_no_text"))
        #expect(DirectAudioASRGatePlanner.decision(
            mode: .inputAudio,
            gateState: .running,
            overallRMS: 0.018
        ) == .allow(reason: "asr_gate_bypassed_strong_rms"))
        #expect(DirectAudioASRGatePlanner.decision(
            mode: .inputAudio,
            gateState: .sawText(characterCount: 4),
            overallRMS: 0.001
        ) == .allow(reason: "asr_gate_saw_text"))
        #expect(DirectAudioASRGatePlanner.decision(
            mode: .inputAudio,
            gateState: .startFailed(errorKind: "speech_not_authorized"),
            overallRMS: 0.001
        ) == .allow(reason: "asr_gate_unavailable"))
        #expect(DirectAudioASRGatePlanner.decision(
            mode: .inputAudio,
            gateState: .bufferOverflowed,
            overallRMS: 0.001
        ) == .allow(reason: "asr_gate_unavailable"))
        #expect(DirectAudioASRGatePlanner.decision(
            mode: .systemASRTextLLM,
            gateState: .running,
            overallRMS: 0.001
        ) == .allow(reason: "not_input_audio"))
        #expect(DirectAudioASRGatePlanner.decision(
            mode: .systemASROnly,
            gateState: .running,
            overallRMS: 0.001
        ) == .allow(reason: "not_input_audio"))
    }

    @Test
    func hudRevealAndShortRecordingPresentationPlannersFavorLowInterruption() {
        #expect(ListeningHUDRevealPlanner.defaultDelaySeconds == 0.10)
        #expect(HUDRevealDelay.defaultDelay == .milliseconds100)
        #expect(HUDRevealDelay.allCases.map(\.rawValue) == [100, 200, 300, 400, 500])
        #expect(HUDRevealDelay.safeSelection(123) == .milliseconds100)
        #expect(HUDRevealDelay.milliseconds100.displayName(in: .chinese).contains("极快"))
        #expect(HUDRevealDelay.milliseconds100.displayName(in: .english).contains("Very Fast"))
        #expect(ListeningHUDRevealPlanner.shouldReveal(isRecording: true, cancelled: false))
        #expect(!ListeningHUDRevealPlanner.shouldReveal(isRecording: false, cancelled: false))
        #expect(!ListeningHUDRevealPlanner.shouldReveal(isRecording: true, cancelled: true))

        #expect(!RecordingStopFailurePresentationPlanner.shouldShowHUD(
            validationStatus: .tooShort,
            listeningHUDWasShown: false
        ))
        #expect(RecordingStopFailurePresentationPlanner.shouldShowHUD(
            validationStatus: .tooShort,
            listeningHUDWasShown: true
        ))
        #expect(RecordingStopFailurePresentationPlanner.shouldShowHUD(
            validationStatus: .tooQuiet,
            listeningHUDWasShown: false
        ))
    }

    @Test
    func idleRecorderCancelKeepsRecorderStopped() {
        let recorder: any RecordingSource = AudioRecorder()
        recorder.cancel()
        #expect(!recorder.isRecording)
    }

    @MainActor
    @Test
    func recordingPipelineCoordinatorCreatesPendingTranscriptionAfterStop() async {
        let result = AudioRecordingResult(
            wavData: WAVEncoder.encodePCM16WAV(samples: Array(repeating: 0.1, count: 16_000)),
            durationSeconds: 1,
            overallRMS: 0.1
        )
        let source = FakePipelineRecordingSource(result: .success(result))
        let coordinator = RecordingPipelineCoordinator()
        let context = makeRecordingStopContext(mode: .inputAudio, validationPolicy: .voiceGated)
        var stoppedResult: AudioRecordingResult?
        var stoppedContext: RecordingStopContext?
        var failedError: Error?

        let task = coordinator.beginStopTask(
            source: source,
            minimumDurationSeconds: 0.5,
            context: context,
            onSuccess: { result, context in
                stoppedResult = result
                stoppedContext = context
            },
            onFailure: { error, _ in
                failedError = error
            }
        )
        await task.value

        #expect(source.stopCount.withValue { $0 } == 1)
        #expect(source.lastMinimumDuration.withValue { $0 } == 0.5)
        #expect(source.lastValidationPolicy.withValue { $0 } == .voiceGated)
        #expect(stoppedResult?.durationSeconds == 1)
        #expect(stoppedContext?.mode == .inputAudio)
        #expect(failedError == nil)
        #expect(coordinator.stopInProgress)

        let pending = coordinator.completeStop(
            result: result,
            context: context,
            liveASRFinalTask: nil
        )
        #expect(pending?.result.durationSeconds == 1)
        #expect(pending?.model == .mimoV25)
        #expect(pending?.instruction == "instruction")
        #expect(pending?.shouldAutoInsert == true)
        #expect(!coordinator.stopInProgress)
        #expect(coordinator.completeStop(result: result, context: context, liveASRFinalTask: nil) == nil)
    }

    @MainActor
    @Test
    func recordingPipelineCoordinatorHandlesStopFailureAndCancellation() async {
        let failingSource = FakePipelineRecordingSource(result: .failure(AudioRecorderError.tooQuiet))
        let coordinator = RecordingPipelineCoordinator()
        let context = makeRecordingStopContext(mode: .systemASRTextLLM, validationPolicy: .durationOnly)
        var failedError: Error?

        let failureTask = coordinator.beginStopTask(
            source: failingSource,
            minimumDurationSeconds: 0.3,
            context: context,
            onSuccess: { _, _ in
                Issue.record("Stop failure should not call success")
            },
            onFailure: { error, _ in
                failedError = error
            }
        )
        await failureTask.value

        #expect((failedError as? AudioRecorderError) == .tooQuiet)
        #expect(coordinator.failStop())
        #expect(!coordinator.failStop())
        #expect(!coordinator.stopInProgress)

        let blockingSource = BlockingPipelineRecordingSource(result: AudioRecordingResult(
            wavData: WAVEncoder.encodePCM16WAV(samples: Array(repeating: 0.1, count: 16_000)),
            durationSeconds: 1,
            overallRMS: 0.1
        ))
        var callbackCalled = false
        let cancellationTask = coordinator.beginStopTask(
            source: blockingSource,
            minimumDurationSeconds: 0.3,
            context: context,
            onSuccess: { _, _ in callbackCalled = true },
            onFailure: { _, _ in callbackCalled = true }
        )
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(blockingSource.waitUntilStopStarted())
        #expect(coordinator.cancelPendingStop())
        cancellationTask.cancel()
        blockingSource.releaseStop()
        await cancellationTask.value
        #expect(!callbackCalled)
        #expect(!coordinator.stopInProgress)
    }

    @Test
    func wavEncoderProduces16kMonoPCM16Header() {
        let samples = (0..<1_600).map { index in Float(sin(Double(index) / 20.0)) * 0.25 }
        let wav = WAVEncoder.encodePCM16WAV(samples: samples)
        #expect(WAVEncoder.validatePCM16Mono16kWAV(wav))
        #expect(String(data: wav[0..<4], encoding: .ascii) == "RIFF")
        #expect(String(data: wav[8..<12], encoding: .ascii) == "WAVE")
    }
    @Test
    func wavEncoderDecodesPCM16Mono16kSamplesAndDuration() {
        let samples = (0..<1_600).map { index in Float(sin(Double(index) / 12.0)) * 0.2 }
        let wav = WAVEncoder.encodePCM16WAV(samples: samples)
        let decoded = WAVEncoder.decodePCM16Mono16kSamples(wav)

        #expect(decoded?.count == samples.count)
        #expect(WAVEncoder.durationSecondsForPCM16Mono16kWAV(wav) == 0.1)
        #expect(decoded?.contains { abs($0) > 0.05 } == true)
    }
}

private func makeRecordingStopContext(
    mode: TranscriptionPipelineMode,
    validationPolicy: RecordingValidationPolicy
) -> RecordingStopContext {
    RecordingStopContext(
        elapsed: 1,
        mode: mode,
        validationPolicy: validationPolicy,
        listeningHUDWasShown: true,
        model: .mimoV25,
        instruction: "instruction",
        styleSelection: .builtIn(.concise),
        shouldAutoInsert: true,
        autoInsertSkipReason: nil,
        originalFocus: nil
    )
}

private final class FakePipelineRecordingSource: RecordingSource, @unchecked Sendable {
    var onRMSLevel: (@Sendable (Float) -> Void)?
    var onSampleChunk: (@Sendable (AudioSampleChunk) -> Void)?
    var isRecording = false

    let stopCount = LockedValue(0)
    let lastMinimumDuration = LockedValue<Double?>(nil)
    let lastValidationPolicy = LockedValue<RecordingValidationPolicy?>(nil)
    private let result: Result<AudioRecordingResult, Error>

    init(result: Result<AudioRecordingResult, Error>) {
        self.result = result
    }

    func start() throws {
        isRecording = true
    }

    func stop(
        minimumDurationSeconds: Double,
        validationPolicy: RecordingValidationPolicy
    ) throws -> AudioRecordingResult {
        stopCount.withValue { $0 += 1 }
        lastMinimumDuration.withValue { $0 = minimumDurationSeconds }
        lastValidationPolicy.withValue { $0 = validationPolicy }
        isRecording = false
        return try result.get()
    }

    func cancel() {
        isRecording = false
    }
}

private final class BlockingPipelineRecordingSource: RecordingSource, @unchecked Sendable {
    var onRMSLevel: (@Sendable (Float) -> Void)?
    var onSampleChunk: (@Sendable (AudioSampleChunk) -> Void)?
    var isRecording = false

    private let result: AudioRecordingResult
    private let started = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)

    init(result: AudioRecordingResult) {
        self.result = result
    }

    func start() throws {
        isRecording = true
    }

    func stop(
        minimumDurationSeconds: Double,
        validationPolicy: RecordingValidationPolicy
    ) throws -> AudioRecordingResult {
        started.signal()
        _ = release.wait(timeout: .now() + 2)
        isRecording = false
        return result
    }

    func cancel() {
        isRecording = false
        releaseStop()
    }

    func waitUntilStopStarted() -> Bool {
        started.wait(timeout: .now() + 2) == .success
    }

    func releaseStop() {
        release.signal()
    }
}
