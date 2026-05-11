import Foundation
import Testing
@testable import OmniVoiceCore

extension ConfigurationTests {

    @Test
    func configLoaderReadsJSONCSourcesAndRedactsSecrets() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnivoice-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("config.jsonc")
        try Data("""
        {
          // JSONC comments are allowed.
          "active_source": "cn",
          "transcription_pipeline": { "mode": "input_audio" },
          "models": {
            "audio_llm": {
              "default_model": "mimo-v2.5",
              "extra_models": ["gpt-audio-1.5"]
            },
            "text_llm": {
              "default_model": "mimo-v2.5",
              "extra_models": ["gpt-5.5"]
            }
          },
          "system_asr": {
            "engine": "classic_speech",
            "keyword_hints_enabled": true
          },
          "sources": {
            "sgp": {
              "base_url": "https://sgp.example.test/v1",
              "api_key": "sgp-secret",
            },
            "cn": {
              "base_url": "https://cn.example.test/v1",
              "api_key": "cn-secret",
            },
          },
          "latency": {
            "enabled": true,
            "interval_seconds": 900,
          },
          "preferences": {
            "ui_language": "en",
            "transcription_style": "rewrite",
            "keyword_hints_enabled": true,
            "enabled_keyword_groups": ["omnivoice_terms", "bad group"],
            "trigger_key": "modifier-left-control",
            "trigger": {
              "continuous_recording_double_tap_enabled": true
            },
            "min_recording_duration_ms": 800,
            "max_recording_duration_seconds": 120,
            "auto_insert": false,
            "launch_at_login": true,
            "hud": {
              "visual_style": "lightCapsule",
              "message_duration_seconds": 5,
              "reveal_delay_ms": 400,
              "live_asr_preview_enabled": true,
            },
          },
          "custom_styles": {
            "support_reply": {
              "display_name": "Support Reply",
              "prompt_lines": [
                "Turn speech into a concise support reply.",
                "Do not invent policy, refund amounts, or deadlines."
              ],
            },
            "bad style": {
              "display_name": "Bad",
              "prompt": "ignored"
            },
            "empty_prompt": {
              "display_name": "Empty",
              "prompt": ""
            },
          },
          "keyword_groups": {
            "omnivoice_terms": {
              "display_name": "OmniVoice 术语",
              "keywords": [
                " OmniVoice ",
                "MiMo",
                "mimo-v2-omni",
                "MiMo",
                "",
                "bad\\nkeyword"
              ],
            },
            "bad group": {
              "display_name": "Bad",
              "keywords": ["ignored"]
            },
          },
        }
        """.utf8).write(to: configURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)

        let loader = ConfigLoader(configFileURL: configURL)

        let config = loader.load()
        #expect(config.baseURL.absoluteString == "https://cn.example.test")
        #expect(config.apiKey == "cn-secret")
        #expect(config.defaultModel == .mimoV25)
        #expect(config.source == .configFile)
        #expect(config.activeSourceID == "cn")
        #expect(config.resolvedSourceID == "cn")
        #expect(config.sources.count == 2)
        #expect(config.latencySettings.interval == .minutes15)
        #expect(config.preferences.uiLanguage == .english)
        #expect(config.preferences.transcriptionStyleSelection.rawValue == "rewrite")
        #expect(config.preferences.keywordHintsEnabled)
        #expect(config.preferences.enabledKeywordGroupIDs == ["omnivoice_terms"])
        #expect(config.preferences.triggerKey == .leftControl)
        #expect(config.preferences.continuousRecordingDoubleTapEnabled == true)
        #expect(config.preferences.minRecordingDuration == .milliseconds800)
        #expect(config.preferences.maxRecordingDuration == .seconds120)
        #expect(config.preferences.autoInsert == false)
        #expect(config.preferences.launchAtLogin == true)
        #expect(config.preferences.hudVisualStyle == .lightCapsule)
        #expect(config.preferences.hudMessageDuration == .seconds5)
        #expect(config.preferences.hudRevealDelay == .milliseconds400)
        #expect(config.preferences.liveASRPreviewEnabled == true)
        #expect(config.customStyles.count == 2)
        let supportReply = try #require(config.customStyles.first(where: { $0.id == "support_reply" }))
        #expect(supportReply.displayName == "Support Reply")
        #expect(supportReply.localizedName(in: .chinese) == "Support Reply")
        #expect(supportReply.localizedDescription(in: .english) == nil)
        #expect(supportReply.prompt.contains("refund amounts") == true)
        #expect(config.customStyles.contains(where: { $0.id == "meeting_notes" }))
        #expect(config.keywordGroups.count == 4)
        let keywordGroup = try #require(config.keywordGroups.first(where: { $0.id == "omnivoice_terms" }))
        #expect(keywordGroup.id == "omnivoice_terms")
        #expect(keywordGroup.localizedName(in: .english) == "OmniVoice 术语")
        #expect(keywordGroup.localizedName(in: .chinese) == "OmniVoice 术语")
        #expect(keywordGroup.keywords == ["OmniVoice", "MiMo", "mimo-v2-omni"])
        let llmGroup = try #require(config.keywordGroups.first(where: { $0.id == "llm_model_terms" }))
        #expect(llmGroup.localizedName(in: .english) == "LLM Models and Companies")
        #expect(llmGroup.keywords.count == 34)
        #expect(llmGroup.keywords.contains("Anthropic"))
        #expect(llmGroup.keywords.contains("Claude Code"))
        #expect(llmGroup.keywords.contains("OpenClaw"))
        #expect(!llmGroup.keywords.contains("GPT-5.5"))
        #expect(config.keywordGroups.contains(where: { $0.id == "mimo_e2e_terms" }))
        #expect(config.keywordGroups.contains(where: { $0.id == "technical_terms" }))
        #expect(config.warnings.contains("Config warning: invalid keyword groups ignored"))
        #expect(config.warnings.contains("Config warning: invalid keywords ignored"))
        #expect(config.redactedStatus.baseURLHost == "cn.example.test")
        #expect(config.redactedStatus.apiKeyConfigured)
        #expect(config.redactedStatus.apiKeyPreview == "••••••")
        #expect(!config.redactedStatus.displayLines.joined().contains("cn-secret"))
    }

    @Test
    func configLoaderParsesDynamicModelCatalogsAndSystemASRSettings() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnivoice-model-catalogs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("config.jsonc")
        try Data("""
        {
          "active_source": "config1",
          "transcription_pipeline": { "mode": "system_asr_text_llm" },
          "models": {
            "audio_llm": {
              "default_model": "qwen3.5-omni-plus",
              "extra_models": ["qwen3.5-omni-plus", "gpt-audio-1.5"]
            },
            "text_llm": {
              "default_model": "gpt-5.5",
              "extra_models": ["gpt-5.5", "qwen3.6-plus"]
            }
          },
          "system_asr": {
            "engine": "apple_online_speech",
            "keyword_hints_enabled": false
          },
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
            "keyword_hints_enabled": true,
            "enabled_keyword_groups": [],
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
        """.utf8).write(to: configURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)

        let config = ConfigLoader(configFileURL: configURL).load()

        #expect(config.pipelineMode == .systemASRTextLLM)
        #expect(config.modelCatalogs.inputAudioDefaultModel.rawValue == "qwen3.5-omni-plus")
        #expect(config.modelCatalogs.inputAudioModels.map(\.rawValue).contains("gpt-audio-1.5"))
        #expect(config.modelCatalogs.textLLMDefaultModel.rawValue == "gpt-5.5")
        #expect(config.systemASRSettings.engine == .appleOnlineSpeech)
        #expect(!config.systemASRSettings.keywordHintsEnabled)
        #expect(config.redactedStatus.displayLines.joined(separator: "\n").contains("Text LLM Model: gpt-5.5"))
    }

    @Test
    func configLoaderMergesUserOverridesWithCanonicalDefaults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnivoice-config-overrides-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("config.jsonc")
        try Data("""
        {
          "active_source": "cn",
          "models": {
            "audio_llm": {
              "default_model": "mimo-v2-omni"
            }
          },
          "sources": {
            "cn": {
              "base_url": "https://cn.example.test",
              "api_key": "cn-secret"
            }
          }
        }
        """.utf8).write(to: configURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)

        let config = ConfigLoader(configFileURL: configURL).load()

        #expect(config.activeSourceID == "cn")
        #expect(config.sources.map(\.id) == ["cn"])
        #expect(config.modelCatalogs.inputAudioDefaultModel == .mimoV2Omni)
        #expect(config.modelCatalogs.inputAudioModels.map(\.rawValue).contains("gpt-audio-1.5"))
        #expect(config.modelCatalogs.textLLMDefaultModel == .mimoV25)
        #expect(config.pipelineMode == .inputAudio)
        #expect(config.systemASRSettings.engine == .speechAnalyzer)
        #expect(config.preferences.triggerKey == .fnGlobe)
        #expect(config.keywordGroups.count == 4)
        #expect(config.keywordGroups.contains(where: { $0.id == "llm_model_terms" }))
    }

    @Test
    func configLoaderReadsSystemASROnlyPipelineMode() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnivoice-system-asr-only-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("config.jsonc")
        try Data("""
        {
          "active_source": "auto",
          "transcription_pipeline": { "mode": "system_asr_only" },
          "system_asr": {
            "engine": "classic_speech",
            "keyword_hints_enabled": true
          },
          "preferences": {
            "ui_language": "zh-Hans",
            "transcription_style": "rewrite",
            "keyword_hints_enabled": false,
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
        """.utf8).write(to: configURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)

        let config = ConfigLoader(configFileURL: configURL).load()

        #expect(config.pipelineMode == .systemASROnly)
        #expect(config.systemASRSettings.engine == .classicSpeech)
        #expect(config.selectedPipelineModelCatalog.isEmpty)
        #expect(config.selectedPipelineModel == .mimoV25)
        #expect(!config.warnings.contains("Config warning: config.jsonc needs at least one source"))
    }

    @Test
    func baseURLNormalizationAndRedaction() {
        #expect(MimoConfig.normalizedBaseURL(from: "https://token-plan-sgp.xiaomimimo.com/v1/")?.absoluteString == "https://token-plan-sgp.xiaomimimo.com")
        #expect(MimoConfig.normalizedBaseURL(from: "https://example.test/custom/v1")?.absoluteString == "https://example.test/custom")
        #expect(MimoConfig.normalizedBaseURL(from: "not a url") == nil)
        #expect(MimoConfig.redactedAPIKey("sk-abcdefghijklmnopqrstuvwxyz") == "sk-ab…wxyz")
    }

    @Test
    func uiLanguageDefaultsToChineseAndPersists() {
        let suiteName = "omnivoice-ui-language-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(LanguagePreference.english.rawValue, forKey: SettingsStore.Key.language)

        let settings = SettingsStore(defaults: defaults)
        #expect(settings.uiLanguage == .chinese)
        #expect(UILanguage.migratedFromLegacyLanguage(LanguagePreference.english.rawValue) == .english)
        settings.uiLanguage = .chinese
        #expect(settings.uiLanguage == .chinese)
        #expect(settings.hudMessageDuration == .seconds3)
        settings.hudMessageDuration = .seconds8
        #expect(settings.hudMessageDuration == .seconds8)
        #expect(settings.minRecordingDuration == .milliseconds500)
        settings.minRecordingDuration = .seconds2
        #expect(settings.minRecordingDuration == .seconds2)
        #expect(settings.hudRevealDelay == .milliseconds100)
        settings.hudRevealDelay = .milliseconds500
        #expect(settings.hudRevealDelay == .milliseconds500)
    }
}
