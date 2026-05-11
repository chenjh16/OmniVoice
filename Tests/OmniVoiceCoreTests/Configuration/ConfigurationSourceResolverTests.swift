import Foundation
import Testing
@testable import OmniVoiceCore

extension ConfigurationTests {

    @Test
    func configSourceNamesAndTemplates() throws {
        #expect(ConfigSourceNameValidator.isValid("config1"))
        #expect(ConfigSourceNameValidator.isValid("work-cn_1"))
        #expect(!ConfigSourceNameValidator.isValid(""))
        #expect(!ConfigSourceNameValidator.isValid("auto"))
        #expect(!ConfigSourceNameValidator.isValid("bad name"))
        #expect(CustomTranscriptionStyleValidator.isValidID("meeting_notes"))
        #expect(!CustomTranscriptionStyleValidator.isValidID("bad style"))
        #expect(!CustomTranscriptionStyleValidator.isValidID("concise"))
        #expect(CustomTranscriptionStyleValidator.isValidPrompt("整理成会议纪要"))
        #expect(!CustomTranscriptionStyleValidator.isValidPrompt(""))

        let chineseTemplate = ConfigTemplateBuilder.template(uiLanguage: .chinese)
        #expect(chineseTemplate.contains(#""active_source": "cn""#))
        #expect(chineseTemplate.contains(#""interval_seconds": 1800"#))
        #expect(chineseTemplate.contains(#""preferences""#))
        #expect(chineseTemplate.contains(#""transcription_pipeline""#))
        #expect(chineseTemplate.contains("system_asr_only"))
        #expect(chineseTemplate.contains(#""audio_llm""#))
        #expect(!chineseTemplate.contains(#""input_audio": {"#))
        #expect(chineseTemplate.contains(#""default_model": "mimo-v2.5""#))
        #expect(chineseTemplate.contains(#""system_asr""#))
        #expect(chineseTemplate.contains(#""mimo-v2-omni""#))
        #expect(chineseTemplate.contains(#""gpt-audio-1.5""#))
        #expect(!chineseTemplate.contains(#""gpt-5.5""#))
        #expect(chineseTemplate.contains(#""engine": "speech_analyzer""#))
        #expect(chineseTemplate.contains(#""transcription_style": "rewrite""#))
        #expect(chineseTemplate.contains(#""max_recording_duration_seconds": 120"#))
        #expect(chineseTemplate.contains(#""launch_at_login": true"#))
        #expect(chineseTemplate.contains(#""reveal_delay_ms": 100"#))
        #expect(chineseTemplate.contains(#""custom_styles""#))
        #expect(chineseTemplate.contains(#""keyword_groups""#))
        #expect(chineseTemplate.contains(#""keyword_hints_enabled": false"#))
        #expect(chineseTemplate.contains(#""enabled_keyword_groups": []"#))
        #expect(!chineseTemplate.contains(#"      "mimo_e2e_terms","#))
        #expect(!chineseTemplate.contains(#""enabled_keyword_groups": ["mimo_e2e_terms""#))
        #expect(chineseTemplate.contains("MiMo E2E Terms"))
        #expect(chineseTemplate.contains("OmniVoice 术语"))
        #expect(chineseTemplate.contains("技术术语"))
        #expect(chineseTemplate.contains("大模型与模型公司"))
        #expect(chineseTemplate.contains("Anthropic"))
        #expect(chineseTemplate.contains("Claude Code"))
        #expect(chineseTemplate.contains("OpenClaw"))
        #expect(chineseTemplate.contains("Qwen3.6"))
        #expect(chineseTemplate.contains("HUD"))
        #expect(chineseTemplate.contains("Fn"))
        #expect(chineseTemplate.contains("自定义转写风格"))
        #expect(chineseTemplate.contains("OmniVoice 会读取"))
        let englishTemplate = ConfigTemplateBuilder.template(uiLanguage: .english)
        #expect(englishTemplate.contains("OmniVoice reads this file"))
        #expect(englishTemplate.contains("system_asr_only"))
        #expect(englishTemplate.contains(#""sources""#))
        #expect(englishTemplate.contains("Delay before the listening HUD appears"))
        #expect(englishTemplate.contains("Custom transcription styles"))
        #expect(englishTemplate.contains("Keyword groups"))
        #expect(englishTemplate.contains("System ASR settings"))
        #expect(englishTemplate.contains(#""engine": "speech_analyzer""#))
        #expect(!englishTemplate.contains(#""allow_apple_server_recognition""#))
        #expect(!englishTemplate.contains(#""display_name_zh""#))
        #expect(!englishTemplate.contains(#""description""#))
        #expect(englishTemplate.contains(#""enabled_keyword_groups": []"#))
        #expect(!englishTemplate.contains(#"      "mimo_e2e_terms","#))
        #expect(englishTemplate.contains("Technical Terms"))
        #expect(englishTemplate.contains("LLM Models and Companies"))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omnivoice-source-name-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configURL = directory.appendingPathComponent("config.jsonc")
        let loader = ConfigLoader(configFileURL: configURL)
        #expect(loader.createTemplateIfMissing(uiLanguage: .english))
        #expect(FileManager.default.fileExists(atPath: configURL.path))
        let rawTemplate = try String(contentsOf: configURL, encoding: .utf8)
        let data = try #require(JSONCNormalizer.normalize(rawTemplate).data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["active_source"] as? String == "cn")
        let sources = try #require(object["sources"] as? [String: Any])
        let cn = try #require(sources["cn"] as? [String: Any])
        let sgp = try #require(sources["sgp"] as? [String: Any])
        #expect(cn["base_url"] as? String == "https://token-plan-cn.xiaomimimo.com")
        #expect(cn["api_key"] as? String == "")
        #expect(sgp["base_url"] as? String == "https://token-plan-sgp.xiaomimimo.com")
        #expect(sgp["api_key"] as? String == "")
        let models = try #require(object["models"] as? [String: Any])
        let textLLM = try #require(models["text_llm"] as? [String: Any])
        #expect(textLLM["default_model"] as? String == "mimo-v2.5")
        #expect(textLLM["extra_models"] == nil)
        let preferences = try #require(object["preferences"] as? [String: Any])
        #expect(preferences["ui_language"] as? String == "en")
        #expect(preferences["transcription_style"] as? String == "rewrite")
        #expect(preferences["keyword_hints_enabled"] as? Bool == false)
        #expect(preferences["enabled_keyword_groups"] as? [String] == [])
        #expect(preferences["max_recording_duration_seconds"] as? Int == 120)
        #expect(preferences["launch_at_login"] as? Bool == true)
        let trigger = try #require(preferences["trigger"] as? [String: Any])
        #expect(trigger["continuous_recording_double_tap_enabled"] as? Bool == false)
        let hud = try #require(preferences["hud"] as? [String: Any])
        #expect(hud["reveal_delay_ms"] as? Int == 100)
        #expect(hud["live_asr_preview_enabled"] as? Bool == false)
        let keywordGroups = try #require(object["keyword_groups"] as? [String: Any])
        #expect(keywordGroups.keys.sorted() == ["llm_model_terms", "mimo_e2e_terms", "omnivoice_terms", "technical_terms"])
        let llmGroup = try #require(keywordGroups["llm_model_terms"] as? [String: Any])
        #expect(llmGroup["display_name"] as? String == "LLM Models and Companies")
        let llmKeywords = try #require(llmGroup["keywords"] as? [String])
        #expect(llmKeywords.count == 34)
        #expect(llmKeywords.contains("OpenAI"))
        #expect(llmKeywords.contains("Claude Code"))
        #expect(llmKeywords.contains("Gemini"))
        #expect(llmKeywords.contains("Qwen3.6"))
        #expect(llmKeywords.contains("OpenClaw"))
        #expect(!llmKeywords.contains("GPT-5.5"))
        #expect(!llmKeywords.contains("Apple Intelligence"))
    }

    @Test
    func apiSourceAutoSelectsFastestReachableSourceWithSpeechModel() throws {
        let sgp = MimoConfigSource(
            id: "sgp",
            baseURL: try #require(URL(string: "https://sgp.example.test")),
            apiKey: "sgp-secret"
        )
        let cn = MimoConfigSource(
            id: "cn",
            baseURL: try #require(URL(string: "https://cn.example.test")),
            apiKey: "cn-secret"
        )
        let failed = MimoConfigSource(
            id: "failed",
            baseURL: try #require(URL(string: "https://failed.example.test")),
            apiKey: "bad-secret"
        )
        let measurements = [
            "sgp": SourceLatencyMeasurement(
                milliseconds: 220,
                httpStatus: 200,
                reachable: true,
                allowedModelIDs: ["mimo-v2-omni"]
            ),
            "cn": SourceLatencyMeasurement(
                milliseconds: 80,
                httpStatus: 200,
                reachable: true,
                allowedModelIDs: ["mimo-v2.5"]
            ),
            "failed": SourceLatencyMeasurement(
                milliseconds: 20,
                httpStatus: 401,
                reachable: false,
                allowedModelIDs: []
            )
        ]
        let resolved = APISourceResolver.resolvedSource(
            activeSourceID: MimoConfig.autoSourceID,
            sources: [failed, sgp, cn],
            latencyResults: measurements
        )
        #expect(resolved?.id == "cn")
        #expect(APISourceResolver.resolvedSource(
            activeSourceID: MimoConfig.autoSourceID,
            sources: [sgp, cn],
            latencyResults: [:]
        )?.id == "sgp")

        let textCatalog = ModelCatalogs(
            inputAudioDefaultModel: .mimoV2Omni,
            inputAudioExtraModels: ["gpt-audio-1.5"],
            textLLMDefaultModel: "gpt-5.5"
        )
        let multiModelMeasurements = [
            "sgp": SourceLatencyMeasurement(
                milliseconds: 220,
                httpStatus: 200,
                reachable: true,
                allowedModelIDs: ["mimo-v2-omni", "gpt-5.5"]
            ),
            "cn": SourceLatencyMeasurement(
                milliseconds: 80,
                httpStatus: 200,
                reachable: true,
                allowedModelIDs: ["mimo-v2.5", "qwen3.6-plus", "mimo-v2.5-tts"]
            )
        ]
        let availability = ModelAvailabilityIndex(
            measurements: multiModelMeasurements,
            catalogs: textCatalog
        )
        #expect(availability.availableModels(for: .inputAudio).map(\.rawValue) == ["mimo-v2-omni", "mimo-v2.5"])
        #expect(Set(availability.availableModels(for: .systemASRTextLLM).map(\.rawValue)) == Set([
            "gpt-5.5",
            "mimo-v2-omni",
            "mimo-v2.5",
            "qwen3.6-plus"
        ]))
        #expect(!availability.availableModels(for: .systemASRTextLLM).map(\.rawValue).contains("mimo-v2.5-tts"))
        #expect(availability.sourceIDsSupporting("gpt-5.5", mode: .systemASRTextLLM) == ["sgp"])
        #expect(availability.sourceIDsSupporting("qwen3.6-plus", mode: .systemASRTextLLM) == ["cn"])
        #expect(availability.sourceIDsSupporting("mimo-v2.5-tts", mode: .systemASRTextLLM).isEmpty)
        #expect(availability.availableModels(for: .systemASROnly).isEmpty)
        #expect(availability.sourceIDsSupporting("gpt-5.5", mode: .systemASROnly).isEmpty)
        #expect(APISourceResolver.resolvedSource(
            activeSourceID: MimoConfig.autoSourceID,
            sources: [sgp, cn],
            latencyResults: multiModelMeasurements,
            modelCatalog: [textCatalog.textLLMDefaultModel],
            requiredModel: "gpt-5.5",
            mode: .systemASROnly
        ) == nil)
        let textResolved = APISourceResolver.resolvedSource(
            activeSourceID: MimoConfig.autoSourceID,
            sources: [sgp, cn],
            latencyResults: multiModelMeasurements,
            modelCatalog: [textCatalog.textLLMDefaultModel],
            requiredModel: "gpt-5.5",
            mode: .systemASRTextLLM
        )
        #expect(textResolved?.id == "sgp")
        let qwenResolved = APISourceResolver.resolvedSource(
            activeSourceID: MimoConfig.autoSourceID,
            sources: [sgp, cn],
            latencyResults: multiModelMeasurements,
            modelCatalog: [textCatalog.textLLMDefaultModel],
            requiredModel: "qwen3.6-plus",
            mode: .systemASRTextLLM
        )
        #expect(qwenResolved?.id == "cn")
    }
}
