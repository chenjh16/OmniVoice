import Foundation
import ApplicationServices
import Testing
@testable import OmniVoiceCore
@testable import OmniVoiceE2ESupport

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
    }

    @Test
    func hudRevealAndShortRecordingPresentationPlannersFavorLowInterruption() {
        #expect(ListeningHUDRevealPlanner.defaultDelaySeconds == 0.20)
        #expect(HUDRevealDelay.defaultDelay == .milliseconds200)
        #expect(HUDRevealDelay.allCases.map(\.rawValue) == [100, 200, 300, 400, 500])
        #expect(HUDRevealDelay.safeSelection(123) == .milliseconds200)
        #expect(HUDRevealDelay.milliseconds200.displayName(in: .chinese).contains("推荐"))
        #expect(HUDRevealDelay.milliseconds200.displayName(in: .english).contains("Recommended"))
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
    @Test
    func wavReplayRecordingSourceEmitsRMSAndReturnsRecordingResult() async throws {
        let samples = (0..<9_600).map { index in Float(sin(Double(index) / 18.0)) * 0.25 }
        let wav = WAVEncoder.encodePCM16WAV(samples: samples)
        let replay = try WAVReplayRecordingSource(wavData: wav, chunkFrameCount: 512, replaySpeed: 40)
        let levels = LockedValue<[Float]>([])
        replay.onRMSLevel = { level in
            levels.withValue { $0.append(level) }
        }

        try replay.start()
        await replay.waitUntilReplayFinished()
        let result = try replay.stop(minimumDurationSeconds: MinRecordingDuration.milliseconds300.seconds)

        #expect(WAVEncoder.validatePCM16Mono16kWAV(result.wavData))
        #expect(result.durationSeconds > 0.5)
        #expect(result.overallRMS > 0.05)
        #expect(levels.withValue { $0.count } > 2)
        #expect(levels.withValue { $0.contains { $0 > 0.1 } })
    }
    @Test
    func wavReplayRecordingSourceRejectsInvalidAndQuietWAV() async throws {
        do {
            _ = try WAVReplayRecordingSource(wavData: Data("not a wav".utf8))
            Issue.record("Invalid WAV should be rejected")
        } catch AudioRecorderError.invalidWAV {
            // Expected.
        } catch {
            Issue.record("Unexpected invalid WAV error: \(error)")
        }

        let quiet = WAVEncoder.encodePCM16WAV(samples: Array(repeating: 0, count: 16_000))
        let replay = try WAVReplayRecordingSource(wavData: quiet, chunkFrameCount: 1_024, replaySpeed: 80)
        try replay.start()
        await replay.waitUntilReplayFinished()
        do {
            _ = try replay.stop(minimumDurationSeconds: MinRecordingDuration.milliseconds300.seconds)
            Issue.record("Quiet WAV should be rejected")
        } catch AudioRecorderError.tooQuiet {
            // Expected.
        } catch {
            Issue.record("Unexpected quiet WAV error: \(error)")
        }
    }
}
