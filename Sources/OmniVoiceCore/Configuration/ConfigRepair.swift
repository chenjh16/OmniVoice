import Foundation

extension ConfigLoader {
    func repairedConfig(from object: [String: Any], uiLanguage: UILanguage) -> MimoConfig? {
        guard let mergedObject = repairMergedConfigObject(from: object, fallbackLanguage: uiLanguage) else { return nil }
        let sources = parseSources(object: mergedObject)
        let parsed = parse(object: mergedObject, source: .configFile, warnings: [])
        guard !sources.isEmpty || parsed.pipelineMode == .systemASROnly else { return nil }
        let activeID: String
        if (mergedObject["active_source"] as? String)?.nilIfBlank == MimoConfig.autoSourceID {
            activeID = MimoConfig.autoSourceID
        } else if let configuredID = (mergedObject["active_source"] as? String)?.nilIfBlank,
                  sources.contains(where: { $0.id == configuredID }) {
            activeID = configuredID
        } else {
            activeID = MimoConfig.autoSourceID
        }
        let selectedModel: AllowedSpeechModel
        let selectedCatalog: [AllowedSpeechModel]
        switch parsed.pipelineMode {
        case .inputAudio:
            selectedModel = parsed.modelCatalogs.inputAudioDefaultModel
            selectedCatalog = parsed.modelCatalogs.inputAudioModels
        case .systemASRTextLLM:
            selectedModel = parsed.modelCatalogs.textLLMDefaultModel
            selectedCatalog = [parsed.modelCatalogs.textLLMDefaultModel]
        case .systemASROnly:
            selectedModel = parsed.modelCatalogs.inputAudioDefaultModel
            selectedCatalog = []
        }
        let selectedSource = APISourceResolver.resolvedSource(
            activeSourceID: activeID,
            sources: sources,
            latencyResults: [:],
            modelCatalog: selectedCatalog,
            requiredModel: selectedModel,
            mode: parsed.pipelineMode
        ) ?? sources.first
        return MimoConfig(
            baseURL: selectedSource?.baseURL ?? MimoConfig.defaultBaseURL,
            apiKey: selectedSource?.apiKey,
            defaultModel: parsed.modelCatalogs.inputAudioDefaultModel,
            source: .configFile,
            activeSourceID: activeID,
            resolvedSourceID: selectedSource?.id ?? activeID,
            sources: sources,
            modelCatalogs: parsed.modelCatalogs,
            pipelineMode: parsed.pipelineMode,
            systemASRSettings: parsed.systemASRSettings,
            customStyles: parsed.customStyles,
            keywordGroups: parsed.keywordGroups,
            latencySettings: parsed.latencySettings,
            preferences: parsed.preferences.with(
                selectedModel: parsed.modelCatalogs.inputAudioDefaultModel,
                uiLanguage: uiLanguage
            )
        )
    }


    func mergedConfigObject(from object: [String: Any], fallbackLanguage: UILanguage) -> [String: Any]? {
        return mergedConfigObject(from: object, fallbackLanguage: fallbackLanguage, allowLegacyModelSection: false)
    }

    func repairMergedConfigObject(from object: [String: Any], fallbackLanguage: UILanguage) -> [String: Any]? {
        mergedConfigObject(from: object, fallbackLanguage: fallbackLanguage, allowLegacyModelSection: true)
    }

    func mergedConfigObject(
        from object: [String: Any],
        fallbackLanguage: UILanguage,
        allowLegacyModelSection: Bool
    ) -> [String: Any]? {
        let normalized = allowLegacyModelSection ? migratingLegacyInputAudioModelSection(in: object) : object
        guard let defaultObject = defaultConfigObject(uiLanguage: preferredLanguage(from: normalized, fallback: fallbackLanguage)) else {
            return nil
        }
        return Self.deepMerge(defaultObject, overridingWith: normalized)
    }

    func defaultConfigObject(uiLanguage: UILanguage) -> [String: Any]? {
        let stripped = JSONCNormalizer.normalize(ConfigDocumentWriter.defaultDocument(uiLanguage: uiLanguage))
        guard let jsonData = stripped.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
    }

    func preferredLanguage(from object: [String: Any], fallback: UILanguage) -> UILanguage {
        guard let preferences = object["preferences"] as? [String: Any],
              let raw = preferences["ui_language"] as? String,
              let language = UILanguage(rawValue: raw) else {
            return fallback
        }
        return language
    }

    func containsLegacyInputAudioModelSection(_ object: [String: Any]) -> Bool {
        guard let models = object["models"] as? [String: Any] else { return false }
        return models["input_audio"] != nil
    }

    func migratingLegacyInputAudioModelSection(in object: [String: Any]) -> [String: Any] {
        guard var models = object["models"] as? [String: Any] else { return object }
        if models["audio_llm"] == nil, let legacy = models["input_audio"] {
            models["audio_llm"] = legacy
        }
        models.removeValue(forKey: "input_audio")
        var output = object
        output["models"] = models
        return output
    }

    static func deepMerge(_ base: [String: Any], overridingWith override: [String: Any]) -> [String: Any] {
        deepMerge(base, overridingWith: override, path: [])
    }

    static func deepMerge(
        _ base: [String: Any],
        overridingWith override: [String: Any],
        path: [String]
    ) -> [String: Any] {
        var output = base
        for (key, overrideValue) in override {
            if path.isEmpty, key == "sources", overrideValue is [String: Any] {
                output[key] = overrideValue
                continue
            }
            if let baseObject = output[key] as? [String: Any],
               let overrideObject = overrideValue as? [String: Any] {
                output[key] = deepMerge(baseObject, overridingWith: overrideObject, path: path + [key])
            } else {
                output[key] = overrideValue
            }
        }
        return output
    }

    func validationIssues(for object: [String: Any], rawObject: [String: Any]) -> [String] {
        var issues: [String] = []
        if rawObject["default_model"] != nil {
            issues.append("default_model_deprecated")
        }
        if containsLegacyInputAudioModelSection(rawObject) {
            issues.append("models_input_audio_deprecated")
        }
        if containsDeprecatedTextLLMExtraModels(rawObject) {
            issues.append("models_text_llm_extra_models_deprecated")
        }
        guard let models = object["models"] as? [String: Any],
              models["audio_llm"] is [String: Any],
              models["text_llm"] is [String: Any] else {
            issues.append("models")
            return issues
        }
        let modelCatalogs = parseModelCatalogs(models)
        let defaultModel = modelCatalogs.inputAudioDefaultModel
        guard let pipeline = object["transcription_pipeline"] as? [String: Any],
              let pipelineMode = TranscriptionPipelineMode(rawValue: pipeline["mode"] as? String ?? "") else {
            issues.append("transcription_pipeline")
            return issues
        }
        let sources = parseSources(object: object)
        if sources.isEmpty, pipelineMode.requiresModelAPI {
            issues.append("sources")
        }
        if let rawSources = object["sources"] as? [String: Any] {
            for (id, value) in rawSources {
                guard ConfigSourceNameValidator.isValid(id),
                      let sourceObject = value as? [String: Any],
                      MimoConfig.normalizedBaseURL(from: sourceObject["base_url"] as? String) != nil,
                      (sourceObject["api_key"] == nil || sourceObject["api_key"] is String) else {
                    issues.append("sources")
                    return issues
                }
            }
        }
        guard let activeID = (object["active_source"] as? String)?.nilIfBlank,
              activeID == MimoConfig.autoSourceID || ConfigSourceNameValidator.isValid(activeID) else {
            issues.append("active_source")
            return issues
        }
        if activeID != MimoConfig.autoSourceID, !sources.contains(where: { $0.id == activeID }) {
            issues.append("active_source_missing")
        }
        for key in ["audio_llm", "text_llm"] {
            guard let section = models[key] as? [String: Any] else { continue }
            guard let defaultModel = section["default_model"] as? String,
                  AllowedSpeechModel(rawValue: defaultModel) != nil else {
                issues.append("models")
                return issues
            }
            guard key == "audio_llm" else { continue }
            if let extraModels = section["extra_models"] {
                guard let values = extraModels as? [String],
                      values.allSatisfy({ AllowedSpeechModel(rawValue: $0) != nil }) else {
                    issues.append("models")
                    return issues
                }
            }
        }
        guard let systemASR = object["system_asr"] as? [String: Any],
              let engine = systemASR["engine"] as? String,
              SystemASREngine(rawValue: engine) != nil else {
            issues.append("system_asr")
            return issues
        }
        if systemASR["allow_apple_server_recognition"] != nil {
            issues.append("system_asr_deprecated")
        }
        if let hints = systemASR["keyword_hints_enabled"], !(hints is Bool) {
            issues.append("system_asr")
            return issues
        }
        if containsDeprecatedCustomMetadata(object["custom_styles"] as? [String: Any]) {
            issues.append("custom_styles_deprecated")
        }
        if containsDeprecatedKeywordMetadata(object["keyword_groups"] as? [String: Any]) {
            issues.append("keyword_groups_deprecated")
        }
        guard let latency = object["latency"] as? [String: Any],
              latency["enabled"] is Bool else {
            issues.append("latency")
            return issues
        }
        if !(latency["interval_seconds"] is NSNull) {
            guard let seconds = latency["interval_seconds"] as? Int,
                  ConfigLatencyInterval(rawValue: seconds) != nil else {
                issues.append("latency_interval")
                return issues
            }
        }
        if parsePreferences(object["preferences"] as? [String: Any], selectedModel: defaultModel) == nil {
            issues.append("preferences")
        }
        return issues
    }

    func preferredWriteLanguage(fallback: UILanguage) -> UILanguage {
        guard let object = readJSONObject(url: configFileURL),
              let mergedObject = mergedConfigObject(from: object, fallbackLanguage: fallback),
              let preferences = parsePreferences(
                mergedObject["preferences"] as? [String: Any],
                selectedModel: parseModelCatalogs(mergedObject["models"] as? [String: Any]).inputAudioDefaultModel
              ) else {
            return fallback
        }
        return preferences.uiLanguage
    }

    func containsDeprecatedCustomMetadata(_ rawStyles: [String: Any]?) -> Bool {
        guard let rawStyles else { return false }
        return rawStyles.values.contains { value in
            guard let object = value as? [String: Any] else { return false }
            return object["display_name_zh"] != nil || object["description"] != nil || object["description_zh"] != nil
        }
    }

    func containsDeprecatedKeywordMetadata(_ rawGroups: [String: Any]?) -> Bool {
        guard let rawGroups else { return false }
        return rawGroups.values.contains { value in
            guard let object = value as? [String: Any] else { return false }
            return object["display_name_zh"] != nil || object["description"] != nil || object["description_zh"] != nil
        }
    }

    func containsDeprecatedTextLLMExtraModels(_ object: [String: Any]) -> Bool {
        guard let models = object["models"] as? [String: Any],
              let textLLM = models["text_llm"] as? [String: Any] else {
            return false
        }
        return textLLM["extra_models"] != nil
    }
}
