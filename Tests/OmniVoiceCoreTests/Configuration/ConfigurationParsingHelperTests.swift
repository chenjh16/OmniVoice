import Foundation
import Testing
@testable import OmniVoiceCore

@Suite("Configuration parsing helpers")
struct ConfigurationParsingHelperTests {
    @Test
    func configWarningsUseStableCodesAndLocalizedMessages() {
        let raw = ConfigWarning.raw(.unreadable)
        #expect(raw == "Config warning: config.jsonc could not be read")
        #expect(UIStrings(language: .chinese).configWarning(raw).contains("无法读取"))
        #expect(UIStrings(language: .english).configWarning(raw).contains("could not be read"))
        #expect(UIStrings(language: .english).configWarning("unknown warning") == "unknown warning")
    }

    @Test
    func identifierValidatorIsSharedByConfigStyleAndKeywordIDs() {
        #expect(ConfigSourceNameValidator.isValid("cn-1"))
        #expect(CustomTranscriptionStyleValidator.isValidID("meeting_notes"))
        #expect(KeywordGroupValidator.isValidID("llm_model_terms"))
        #expect(!ConfigSourceNameValidator.isValid("auto"))
        #expect(!CustomTranscriptionStyleValidator.isValidID("rewrite"))
        #expect(!KeywordGroupValidator.isValidID("_bad"))
    }

    @Test
    func preferenceParserFallsBackFieldByField() {
        let loader = ConfigLoader(configFileURL: URL(fileURLWithPath: "/tmp/unused.jsonc"))
        let preferences = loader.parsePreferences(
            [
                "ui_language": "en",
                "transcription_style": "not-a-style",
                "trigger_key": "fn-globe",
                "auto_insert": false,
                "hud": [
                    "visual_style": "automatic",
                    "message_duration_seconds": 999,
                    "reveal_delay_ms": 100
                ]
            ],
            selectedModel: AllowedSpeechModel.defaultInputAudioModel
        )
        #expect(preferences.uiLanguage == UILanguage.english)
        #expect(preferences.transcriptionStyleSelection == TranscriptionStyleSelection.defaultSelection)
        #expect(preferences.autoInsert == false)
        #expect(preferences.hudMessageDuration == HUDMessageDuration.defaultDuration)
        #expect(preferences.hudRevealDelay == HUDRevealDelay.milliseconds100)
    }
}
