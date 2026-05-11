import Testing
@testable import OmniVoiceCore

@Suite("HUD waveform")
struct HUDWaveformTests {
    @Test
    func waveformMotionUsesIdleAndSpeechGate() {
        let idle = WaveformMotionResolver.resolve(level: 0.01, impulse: 0.0, secondsSinceSpeech: 2.0)
        let active = WaveformMotionResolver.resolve(level: 0.22, impulse: 0.0, secondsSinceSpeech: nil)
        let releaseHeld = WaveformMotionResolver.resolve(level: 0.01, impulse: 0.0, secondsSinceSpeech: 0.12)
        let released = WaveformMotionResolver.resolve(level: 0.01, impulse: 0.0, secondsSinceSpeech: 0.35)
        #expect(!idle.active)
        #expect(active.active)
        #expect(releaseHeld.active)
        #expect(!released.active)
        #expect(active.phaseStep > idle.phaseStep * 2)
        #expect(releaseHeld.phaseStep > idle.phaseStep)
    }

    @Test
    func transcriptionTailPreviewFormatterKeepsShortTextAndPrefixesLongText() {
        #expect(HUDPreviewTextFormatter.transcriptionTail("short", limit: 44) == "short")
        let long = String(repeating: "a", count: 60)
        let formatted = HUDPreviewTextFormatter.transcriptionTail(long, limit: 44)
        #expect(formatted.hasPrefix("…"))
        #expect(formatted.count == 45)
        #expect(long.hasSuffix(String(formatted.dropFirst())))
    }
}
