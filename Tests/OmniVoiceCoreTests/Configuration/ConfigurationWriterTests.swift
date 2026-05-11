import Foundation
import Testing
@testable import OmniVoiceCore

extension ConfigurationTests {

    @Test
    func defaultConfigDocumentIsNewSchemaAndKeepsReadableMultilineLists() throws {
        let raw = ConfigDocumentWriter.defaultDocument(uiLanguage: .english)
        #expect(raw.contains(#""audio_llm""#))
        #expect(raw.contains(#""text_llm""#))
        #expect(raw.contains(#""system_asr""#))
        #expect(raw.contains(#""llm_model_terms""#))
        #expect(raw.contains(#"""
      "extra_models": [
"""#))
        #expect(raw.contains(#"""
      "keywords": [
"""#))
        #expect(!raw.contains(#""input_audio": {"#))
        #expect(!raw.contains("display_name_zh"))
        #expect(!raw.contains("description_zh"))
        #expect(!raw.contains("allow_apple_server_recognition"))

        let normalized = try #require(JSONCNormalizer.normalize(raw).data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: normalized) as? [String: Any])
        let models = try #require(object["models"] as? [String: Any])
        let audioLLM = try #require(models["audio_llm"] as? [String: Any])
        let textLLM = try #require(models["text_llm"] as? [String: Any])
        #expect(object["default_model"] == nil)
        #expect(audioLLM["default_model"] as? String == "mimo-v2.5")
        #expect(audioLLM["extra_models"] is [String])
        #expect(textLLM["default_model"] as? String == "mimo-v2.5")
        #expect(textLLM["extra_models"] == nil)
    }

    @MainActor
    @Test
    func appConfigStoreOwnsEffectiveConfigAndSerializesJSONC() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnivoice-config-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("config.jsonc")
        try Data("""
        {
          "active_source": "cn",
          "sources": {
            "cn": {
              "base_url": "https://cn.example.test",
              "api_key": ""
            }
          },
          "preferences": {
            "ui_language": "en",
            "transcription_style": "rewrite",
            "keyword_hints_enabled": true,
            "enabled_keyword_groups": ["omnivoice_terms"],
            "trigger_key": "fn-globe",
            "min_recording_duration_ms": 500,
            "max_recording_duration_seconds": 120,
            "auto_insert": true,
            "launch_at_login": true,
            "hud": {
              "visual_style": "automatic",
              "message_duration_seconds": 3,
              "reveal_delay_ms": 100
            }
          }
        }
        """.utf8).write(to: configURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)

        let store = AppConfigStore(
            loader: ConfigLoader(configFileURL: configURL),
            initialUILanguage: .english
        )
        #expect(store.config.activeSourceID == "cn")
        #expect(store.config.modelCatalogs.inputAudioDefaultModel == .mimoV25)
        #expect(store.config.modelCatalogs.textLLMDefaultModel == .mimoV25)
        #expect(store.config.preferences.uiLanguage == .english)

        store.updatePreferencesInMemory {
            $0.updating(
                transcriptionStyleSelection: .builtIn(.verbatim),
                autoInsert: false
            )
        }
        #expect(store.config.preferences.transcriptionStyleSelection == .builtIn(.verbatim))
        #expect(store.config.preferences.autoInsert == false)
        #expect(store.serializedDocument().contains(#""transcription_style": "verbatim""#))
        #expect(store.serializedDocument().contains(#""auto_insert": false"#))

        #expect(store.saveModelAndPipelineSettings(
            inputAudioModel: .mimoV2Omni,
            textLLMModel: .mimoV25Pro,
            pipelineMode: .systemASRTextLLM,
            systemASRSettings: SystemASRSettings(engine: .classicSpeech, keywordHintsEnabled: false),
            uiLanguage: .english
        ))
        #expect(store.config.modelCatalogs.inputAudioDefaultModel == .mimoV2Omni)
        #expect(store.config.modelCatalogs.textLLMDefaultModel == .mimoV25Pro)
        #expect(store.config.pipelineMode == .systemASRTextLLM)
        #expect(store.config.systemASRSettings == SystemASRSettings(engine: .classicSpeech, keywordHintsEnabled: false))

        let object = try jsoncObject(from: configURL)
        let models = try #require(object["models"] as? [String: Any])
        let audioLLM = try #require(models["audio_llm"] as? [String: Any])
        let textLLM = try #require(models["text_llm"] as? [String: Any])
        #expect(audioLLM["default_model"] as? String == "mimo-v2-omni")
        #expect(textLLM["default_model"] as? String == "mimo-v2.5-pro")
        #expect(textLLM["extra_models"] == nil)
        let pipeline = try #require(object["transcription_pipeline"] as? [String: Any])
        #expect(pipeline["mode"] as? String == "system_asr_text_llm")
        let systemASR = try #require(object["system_asr"] as? [String: Any])
        #expect(systemASR["engine"] as? String == "classic_speech")
        #expect(systemASR["keyword_hints_enabled"] as? Bool == false)

        #expect(store.saveModelAndPipelineSettings(
            inputAudioModel: .mimoV25,
            textLLMModel: .mimoV25Pro,
            pipelineMode: .systemASROnly,
            systemASRSettings: SystemASRSettings(engine: .classicSpeech, keywordHintsEnabled: true),
            uiLanguage: .english
        ))
        #expect(store.config.pipelineMode == .systemASROnly)
        let systemOnlyObject = try jsoncObject(from: configURL)
        let systemOnlyPipeline = try #require(systemOnlyObject["transcription_pipeline"] as? [String: Any])
        #expect(systemOnlyPipeline["mode"] as? String == "system_asr_only")
    }

    @Test
    func configMenuStateWritesAnnotatedJSONCAndPreservesSupportedFields() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnivoice-save-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("config.jsonc")
        try Data("""
        {
          "active_source": "primary",
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
          "custom_flag": true,
          "sources": {
            "primary": {
              "base_url": "https://old.example.test",
              "api_key": "old-secret"
            },
            "backup": {
              "base_url": "https://backup.example.test",
              "api_key": "backup-secret"
            }
          },
          "latency": {
            "enabled": true,
            "interval_seconds": 1800
          },
          "preferences": {
            "ui_language": "zh-Hans",
            "transcription_style": "concise",
            "keyword_hints_enabled": true,
            "enabled_keyword_groups": ["meeting_terms"],
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
          },
          "custom_styles": {
            "meeting_notes": {
              "display_name": "Meeting Notes",
              "prompt": "Keep action items."
            }
          },
          "keyword_groups": {
            "meeting_terms": {
              "display_name": "Meeting Terms",
              "keywords": ["OmniVoice", "MiMo"]
            }
          }
        }
        """.utf8).write(to: configURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: configURL.path)

        let loader = ConfigLoader(configFileURL: configURL)
        #expect(loader.saveActiveSource("backup"))
        #expect(loader.saveLatencyInterval(.startupOnly))
        let preferences = ConfigPreferences(
            selectedModel: .mimoV2Omni,
            uiLanguage: .english,
            transcriptionStyleSelection: .builtIn(.rewrite),
            keywordHintsEnabled: true,
            enabledKeywordGroupIDs: ["meeting_terms"],
            triggerKey: .leftControl,
            minRecordingDuration: .milliseconds300,
            maxRecordingDuration: .seconds15,
            autoInsert: false,
            launchAtLogin: true,
            hudVisualStyle: .darkCapsule,
            hudMessageDuration: .seconds12,
            hudRevealDelay: .milliseconds500,
            liveASRPreviewEnabled: true
        )
        #expect(loader.savePreferences(preferences))

        let data = try Data(contentsOf: configURL)
        let raw = try #require(String(data: data, encoding: .utf8))
        #expect(raw.contains("OmniVoice reads this file"))
        #expect(raw.contains("HUD visual style"))
        let object = try jsoncObject(from: configURL)
        #expect(object["default_model"] == nil)
        let models = try #require(object["models"] as? [String: Any])
        #expect(models["input_audio"] == nil)
        let inputAudio = try #require(models["audio_llm"] as? [String: Any])
        #expect(inputAudio["default_model"] as? String == "mimo-v2-omni")
        let textLLM = try #require(models["text_llm"] as? [String: Any])
        #expect(textLLM["default_model"] as? String == "mimo-v2.5")
        #expect(textLLM["extra_models"] == nil)
        let pipeline = try #require(object["transcription_pipeline"] as? [String: Any])
        #expect(pipeline["mode"] as? String == "input_audio")
        let systemASR = try #require(object["system_asr"] as? [String: Any])
        #expect(systemASR["engine"] as? String == "classic_speech")
        #expect(systemASR["allow_apple_server_recognition"] == nil)
        #expect(object["custom_flag"] == nil)
        #expect(object["active_source"] as? String == "backup")
        let sources = try #require(object["sources"] as? [String: Any])
        let primary = try #require(sources["primary"] as? [String: Any])
        let backup = try #require(sources["backup"] as? [String: Any])
        #expect(primary["base_url"] as? String == "https://old.example.test")
        #expect(primary["api_key"] as? String == "old-secret")
        #expect(backup["base_url"] as? String == "https://backup.example.test")
        #expect(backup["api_key"] as? String == "backup-secret")
        let customStyles = try #require(object["custom_styles"] as? [String: Any])
        let meetingNotes = try #require(customStyles["meeting_notes"] as? [String: Any])
        #expect(meetingNotes["display_name_zh"] == nil)
        #expect(meetingNotes["description"] == nil)
        let promptLines = try #require(meetingNotes["prompt_lines"] as? [String])
        #expect(promptLines.joined(separator: "\n") == "Keep action items.")
        let latency = try #require(object["latency"] as? [String: Any])
        #expect(latency["enabled"] as? Bool == true)
        #expect(latency["interval_seconds"] is NSNull)
        let savedPreferences = try #require(object["preferences"] as? [String: Any])
        #expect(savedPreferences["ui_language"] as? String == "en")
        #expect(savedPreferences["transcription_style"] as? String == "rewrite")
        #expect(savedPreferences["keyword_hints_enabled"] as? Bool == true)
        #expect(savedPreferences["enabled_keyword_groups"] as? [String] == ["meeting_terms"])
        #expect(savedPreferences["trigger_key"] as? String == "modifier-left-control")
        #expect(savedPreferences["min_recording_duration_ms"] as? Int == 300)
        #expect(savedPreferences["max_recording_duration_seconds"] as? Int == 15)
        #expect(savedPreferences["auto_insert"] as? Bool == false)
        #expect(savedPreferences["launch_at_login"] as? Bool == true)
        let hud = try #require(savedPreferences["hud"] as? [String: Any])
        #expect(hud["visual_style"] as? String == "darkCapsule")
        #expect(hud["message_duration_seconds"] as? Int == 12)
        #expect(hud["reveal_delay_ms"] as? Int == 500)
        #expect(hud["live_asr_preview_enabled"] as? Bool == true)
        let keywordGroups = try #require(object["keyword_groups"] as? [String: Any])
        let meetingTerms = try #require(keywordGroups["meeting_terms"] as? [String: Any])
        #expect(meetingTerms["display_name"] as? String == "Meeting Terms")
        #expect(meetingTerms["description"] == nil)
        #expect(meetingTerms["keywords"] as? [String] == ["OmniVoice", "MiMo"])
        let permissions = try FileManager.default.attributesOfItem(atPath: configURL.path)[.posixPermissions] as? NSNumber
        #expect((permissions?.intValue ?? 0) & 0o777 == 0o600)
    }

    @Test
    func configPreferencesKeepKeywordEnableStateAlignedWithSelection() {
        let base = ConfigPreferences.defaultPreferences(selectedModel: .mimoV25, uiLanguage: .chinese)
        let disabled = base.updating(
            keywordHintsEnabled: false,
            enabledKeywordGroupIDs: ["meeting_terms"]
        )
        #expect(!disabled.keywordHintsEnabled)
        #expect(disabled.enabledKeywordGroupIDs.isEmpty)

        let enabled = base.updating(
            keywordHintsEnabled: true,
            enabledKeywordGroupIDs: ["meeting_terms", "meeting_terms", "bad group"]
        )
        #expect(enabled.keywordHintsEnabled)
        #expect(enabled.enabledKeywordGroupIDs == ["meeting_terms"])

        let enabledWithoutGroups = base.updating(
            keywordHintsEnabled: true,
            enabledKeywordGroupIDs: []
        )
        #expect(!enabledWithoutGroups.keywordHintsEnabled)
        #expect(enabledWithoutGroups.enabledKeywordGroupIDs.isEmpty)
    }

    @Test
    func configWriterRewritesCommentLanguageFromPreferences() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnivoice-comment-language-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("config.jsonc")
        let loader = ConfigLoader(configFileURL: configURL)
        _ = loader.ensureValidConfig(uiLanguage: .chinese)
        var preferences = ConfigPreferences.defaultPreferences(selectedModel: .defaultModel, uiLanguage: .english)
        #expect(loader.savePreferences(preferences))
        var raw = try String(contentsOf: configURL, encoding: .utf8)
        #expect(raw.contains("OmniVoice reads this file"))
        #expect(!raw.contains("OmniVoice 会读取"))

        preferences = preferences.with(uiLanguage: .chinese)
        #expect(loader.savePreferences(preferences))
        raw = try String(contentsOf: configURL, encoding: .utf8)
        #expect(raw.contains("OmniVoice 会读取"))
        #expect(!raw.contains("OmniVoice reads this file"))
    }
}
