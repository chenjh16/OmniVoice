import Foundation
import Testing
@testable import OmniVoiceCore
@testable import OmniVoiceE2ESupport

@Suite("WAV replay recording source")
struct WAVReplayRecordingSourceTests {
    @Test
    func wavReplayRecordingSourceEmitsRMSAndReturnsRecordingResult() async throws {
        let samples = (0..<9_600).map { index in Float(sin(Double(index) / 18.0)) * 0.25 }
        let wav = WAVEncoder.encodePCM16WAV(samples: samples)
        let replay = try WAVReplayRecordingSource(wavData: wav, chunkFrameCount: 512, replaySpeed: 40)
        let levels = LockedValue<[Float]>([])
        let chunks = LockedValue<[AudioSampleChunk]>([])
        replay.onRMSLevel = { level in
            levels.withValue { $0.append(level) }
        }
        replay.onSampleChunk = { chunk in
            chunks.withValue { $0.append(chunk) }
        }

        try replay.start()
        await replay.waitUntilReplayFinished()
        let result = try replay.stop(minimumDurationSeconds: MinRecordingDuration.milliseconds300.seconds)

        #expect(WAVEncoder.validatePCM16Mono16kWAV(result.wavData))
        #expect(result.durationSeconds > 0.5)
        #expect(result.overallRMS > 0.05)
        #expect(levels.withValue { $0.count } > 2)
        #expect(levels.withValue { $0.contains { $0 > 0.1 } })
        #expect(chunks.withValue { $0.count } > 2)
        #expect(chunks.withValue { $0.allSatisfy { $0.sampleRate == 16_000 && !$0.samples.isEmpty } })
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

        let systemASRReplay = try WAVReplayRecordingSource(wavData: quiet, chunkFrameCount: 1_024, replaySpeed: 80)
        try systemASRReplay.start()
        await systemASRReplay.waitUntilReplayFinished()
        let result = try systemASRReplay.stop(
            minimumDurationSeconds: MinRecordingDuration.milliseconds300.seconds,
            validationPolicy: .durationOnly
        )
        #expect(WAVEncoder.validatePCM16Mono16kWAV(result.wavData))
        #expect(result.durationSeconds >= 1.0)
        #expect(result.overallRMS < RecordingValidator.minimumEffectiveRMS)
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withValue<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
