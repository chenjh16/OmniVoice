import Foundation
import Testing
@testable import OmniVoiceCore

extension ConfigurationTests {

    @Test
    func ensureValidConfigMigratesDeprecatedInputAudioModelSection() throws {
        let fixture = try configFixture(slug: "omnivoice-config-legacy-input-audio")
        try fixture.write("""
        {
          "active_source": "cn",
          "transcription_pipeline": { "mode": "input_audio" },
          "models": {
            "input_audio": {
              "default_model": "mimo-v2-omni",
              "extra_models": ["gpt-audio-1.5"]
            },
            "text_llm": {
              "default_model": "mimo-v2-pro",
              "extra_models": ["mimo-v2.5-pro"]
            }
          },
          "sources": {
            "cn": {
              "base_url": "https://cn.example.test",
              "api_key": "cn-secret"
            }
          }
        }
        """)

        let loader = fixture.loader
        #expect(loader.loadValidConfigWithoutRepair() == .invalid([
            "models_input_audio_deprecated",
            "models_text_llm_extra_models_deprecated"
        ]))
        let migrated = loader.ensureValidConfig(uiLanguage: .english)

        #expect(migrated.modelCatalogs.inputAudioDefaultModel == .mimoV2Omni)
        #expect(migrated.modelCatalogs.textLLMDefaultModel == .mimoV2Pro)
        #expect(try fixture.backupNames().count == 1)
        let object = try fixture.object()
        let models = try #require(object["models"] as? [String: Any])
        #expect(models["input_audio"] == nil)
        let audioLLM = try #require(models["audio_llm"] as? [String: Any])
        #expect(audioLLM["default_model"] as? String == "mimo-v2-omni")
        let textLLM = try #require(models["text_llm"] as? [String: Any])
        #expect(textLLM["extra_models"] == nil)
    }

    @Test
    func ensureValidConfigRemovesDeprecatedTextLLMExtraModels() throws {
        let fixture = try configFixture(slug: "omnivoice-config-legacy-text-extra")
        try fixture.write("""
        {
          "active_source": "cn",
          "transcription_pipeline": { "mode": "system_asr_text_llm" },
          "models": {
            "audio_llm": {
              "default_model": "mimo-v2.5",
              "extra_models": ["mimo-v2-omni"]
            },
            "text_llm": {
              "default_model": "mimo-v2-pro",
              "extra_models": ["mimo-v2.5-pro", "gpt-5.5"]
            }
          },
          "system_asr": { "engine": "classic_speech", "keyword_hints_enabled": true },
          "sources": {
            "cn": {
              "base_url": "https://cn.example.test",
              "api_key": "cn-secret"
            }
          },
          "latency": { "enabled": true, "interval_seconds": 1800 },
          "preferences": {
            "ui_language": "en",
            "transcription_style": "rewrite",
            "keyword_hints_enabled": true,
            "enabled_keyword_groups": [],
            "trigger_key": "fn-globe",
            "min_recording_duration_ms": 500,
            "max_recording_duration_seconds": 120,
            "auto_insert": true,
            "launch_at_login": true,
            "hud": {
              "visual_style": "automatic",
              "message_duration_seconds": 3,
              "reveal_delay_ms": 100,
              "live_asr_preview_enabled": false
            }
          }
        }
        """)

        let loader = fixture.loader
        #expect(loader.loadValidConfigWithoutRepair() == .invalid(["models_text_llm_extra_models_deprecated"]))
        let repaired = loader.ensureValidConfig(uiLanguage: .english)

        #expect(repaired.modelCatalogs.textLLMDefaultModel == .mimoV2Pro)
        #expect(try fixture.backupNames().count == 1)
        let object = try fixture.object()
        let models = try #require(object["models"] as? [String: Any])
        let textLLM = try #require(models["text_llm"] as? [String: Any])
        #expect(textLLM["default_model"] as? String == "mimo-v2-pro")
        #expect(textLLM["extra_models"] == nil)
    }

    @Test
    func configLoaderBacksUpAndRebuildsIncompleteConfig() throws {
        let fixture = try configFixture(slug: "omnivoice-config-canonical")
        try fixture.write("""
        {
          "base_url": "https://old.example.test",
          "api_key": "old-secret",
          "default_model": "mimo-v2.5"
        }
        """)

        let loader = fixture.loader
        let rebuilt = loader.ensureValidConfig(uiLanguage: .chinese)
        #expect(rebuilt.source == .configFile)
        #expect(rebuilt.activeSourceID == "cn")
        #expect(rebuilt.resolvedSourceID == "cn")
        #expect(rebuilt.apiKey == nil)
        #expect(rebuilt.preferences.uiLanguage == .chinese)
        #expect(rebuilt.preferences.hudRevealDelay == .milliseconds100)
        #expect(rebuilt.customStyles.first?.id == "meeting_notes")
        #expect(try fixture.backupNames().count == 1)

        let fallbackURL = fixture.directory.appendingPathComponent("config.json")
        try Data("""
        {
          "active_source": "fallback",
          "sources": {
            "fallback": {
              "base_url": "https://fallback.example.test",
              "api_key": "fallback-secret"
            }
          }
        }
        """.utf8).write(to: fallbackURL)
        let missingFallback = ConfigLoader(configFileURL: fixture.directory.appendingPathComponent("missing.jsonc")).load()
        #expect(missingFallback.source == .missing)
        #expect(missingFallback.apiKey == nil)
    }

    @Test
    func ensureValidConfigRebuildsBadJSONEmptySourcesAndInvalidPreferences() throws {
        let cases = [
            ("bad-json", "{ nope"),
            ("empty-sources", """
            {
              "active_source": "auto",
              "transcription_pipeline": { "mode": "input_audio" },
              "models": {
                "audio_llm": { "default_model": "mimo-v2.5", "extra_models": [] },
                "text_llm": { "default_model": "mimo-v2.5" }
              },
              "system_asr": { "engine": "classic_speech", "keyword_hints_enabled": true },
              "sources": {},
              "latency": { "enabled": true, "interval_seconds": 1800 },
              "preferences": {
                "ui_language": "en",
                "transcription_style": "concise",
                "trigger_key": "fn-globe",
                "min_recording_duration_ms": 500,
                "max_recording_duration_seconds": 60,
                "auto_insert": true,
                "launch_at_login": false,
                "hud": {
                  "visual_style": "automatic",
                  "message_duration_seconds": 3,
                  "reveal_delay_ms": 200
                }
              }
            }
            """),
            ("bad-preferences", """
            {
              "active_source": "config1",
              "transcription_pipeline": { "mode": "input_audio" },
              "models": {
                "audio_llm": { "default_model": "mimo-v2.5", "extra_models": [] },
                "text_llm": { "default_model": "mimo-v2.5" }
              },
              "system_asr": { "engine": "classic_speech", "keyword_hints_enabled": true },
              "sources": {
                "config1": {
                  "base_url": "https://example.test",
                  "api_key": ""
                }
              },
              "latency": { "enabled": true, "interval_seconds": 1800 },
              "preferences": {
                "ui_language": "en",
                "transcription_style": "concise",
                "trigger_key": "fn-globe",
                "min_recording_duration_ms": 500,
                "max_recording_duration_seconds": 60,
                "auto_insert": true,
                "launch_at_login": false,
                "hud": {
                  "visual_style": "automatic",
                  "message_duration_seconds": 3,
                  "reveal_delay_ms": 999
                }
              }
            }
            """)
        ]

        for (name, text) in cases {
            let fixture = try configFixture(slug: "omnivoice-\(name)")
            try fixture.write(text)

            let rebuilt = fixture.loader.ensureValidConfig(uiLanguage: .english)
            #expect(rebuilt.source == .configFile)
            #expect(rebuilt.resolvedSourceID == (name == "bad-preferences" ? "config1" : "cn"))
            #expect(rebuilt.preferences.uiLanguage == .english)
            #expect(rebuilt.preferences.hudRevealDelay == .milliseconds100)
            #expect(try fixture.backupNames().count == 1)
        }
    }
}
