import Foundation
import ApplicationServices
import Testing
@testable import OmniVoiceCore
@testable import OmniVoiceE2ESupport

@Suite("Model filtering")
struct ModelFilteringTests {
    @Test
    func modelFilteringAllowsOnlySpeechModels() {
        let ids = [
            "mimo-v2-omni",
            "mimo-v2.5",
            "mimo-v2-pro",
            "mimo-v2.5-pro",
            "mimo-v2-tts",
            "mimo-v2.5-tts",
            "mimo-v2.5-tts-voiceclone",
            "mimo-v2.5-tts-voicedesign"
        ]
        #expect(AllowedSpeechModel.filterSpeechModels(from: ids).map(\.rawValue) == ["mimo-v2-omni", "mimo-v2.5"])
    }
}
