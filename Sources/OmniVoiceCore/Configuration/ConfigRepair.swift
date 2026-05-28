import Foundation

extension ConfigLoader {
    func repairedConfig(from object: [String: Any], uiLanguage: UILanguage) -> MimoConfig? {
        guard let mergedObject = repairMergedConfigObject(from: object, fallbackLanguage: uiLanguage) else { return nil }
        let sources = parseSources(object: mergedObject)
        let parsed = parse(object: mergedObject, source: .configFile, warnings: [])
        guard !sources.isEmpty || parsed.pipelineMode == .systemASROnly else { return nil }
        let activeID: String
        if (mergedObject[ConfigSchema.Root.activeSource] as? String)?.nilIfBlank == MimoConfig.autoSourceID {
            activeID = MimoConfig.autoSourceID
        } else if let configuredID = (mergedObject[ConfigSchema.Root.activeSource] as? String)?.nilIfBlank,
                  sources.contains(where: { $0.id == configuredID }) {
            activeID = configuredID
        } else {
            activeID = MimoConfig.autoSourceID
        }
        let modelSelection = PipelineModelSelectionPlanner.selection(
            mode: parsed.pipelineMode,
            catalogs: parsed.modelCatalogs
        )
        let selectedSource = APISourceResolver.resolvedSource(
            activeSourceID: activeID,
            sources: sources,
            latencyResults: [:],
            modelCatalog: modelSelection.modelCatalog,
            requiredModel: modelSelection.selectedModel,
            mode: parsed.pipelineMode
        ) ?? sources.first
        return MimoConfig(
            baseURL: selectedSource?.baseURL ?? MimoConfig.defaultBaseURL,
            apiKey: selectedSource?.apiKey,
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
        guard let preferences = object[ConfigSchema.Root.preferences] as? [String: Any],
              let raw = preferences[ConfigSchema.Preferences.uiLanguage] as? String,
              let language = UILanguage(rawValue: raw) else {
            return fallback
        }
        return language
    }

    func containsLegacyInputAudioModelSection(_ object: [String: Any]) -> Bool {
        guard let models = object[ConfigSchema.Root.models] as? [String: Any] else { return false }
        return models[ConfigSchema.Models.legacyInputAudio] != nil
    }

    func migratingLegacyInputAudioModelSection(in object: [String: Any]) -> [String: Any] {
        guard var models = object[ConfigSchema.Root.models] as? [String: Any] else { return object }
        if models[ConfigSchema.Models.audioLLM] == nil, let legacy = models[ConfigSchema.Models.legacyInputAudio] {
            models[ConfigSchema.Models.audioLLM] = legacy
        }
        models.removeValue(forKey: ConfigSchema.Models.legacyInputAudio)
        var output = object
        output[ConfigSchema.Root.models] = models
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
        if rawObject[ConfigSchema.Root.deprecatedDefaultModel] != nil {
            issues.append("default_model_deprecated")
        }
        if containsLegacyInputAudioModelSection(rawObject) {
            issues.append("models_input_audio_deprecated")
        }
        if containsDeprecatedTextLLMExtraModels(rawObject) {
            issues.append("models_text_llm_extra_models_deprecated")
        }
        guard let models = object[ConfigSchema.Root.models] as? [String: Any],
              ConfigSchema.Models.requiredSections.allSatisfy({ models[$0] is [String: Any] }) else {
            issues.append("models")
            return issues
        }
        _ = parseModelCatalogs(models)
        guard let pipeline = object[ConfigSchema.Root.transcriptionPipeline] as? [String: Any],
              let pipelineMode = TranscriptionPipelineMode(rawValue: pipeline[ConfigSchema.Pipeline.mode] as? String ?? "") else {
            issues.append("transcription_pipeline")
            return issues
        }
        let sources = parseSources(object: object)
        if sources.isEmpty, pipelineMode.requiresModelAPI {
            issues.append("sources")
        }
        if let rawSources = object[ConfigSchema.Root.sources] as? [String: Any] {
            for (id, value) in rawSources {
                guard ConfigSourceNameValidator.isValid(id),
                      let sourceObject = value as? [String: Any],
                      MimoConfig.normalizedBaseURL(from: sourceObject[ConfigSchema.Source.baseURL] as? String) != nil,
                      (sourceObject[ConfigSchema.Source.apiKey] == nil || sourceObject[ConfigSchema.Source.apiKey] is String) else {
                    issues.append("sources")
                    return issues
                }
            }
        }
        guard let activeID = (object[ConfigSchema.Root.activeSource] as? String)?.nilIfBlank,
              activeID == MimoConfig.autoSourceID || ConfigSourceNameValidator.isValid(activeID) else {
            issues.append("active_source")
            return issues
        }
        if activeID != MimoConfig.autoSourceID, !sources.contains(where: { $0.id == activeID }) {
            issues.append("active_source_missing")
        }
        for key in ConfigSchema.Models.requiredSections {
            guard let section = models[key] as? [String: Any] else { continue }
            guard let defaultModel = section[ConfigSchema.Models.defaultModel] as? String,
                  AllowedSpeechModel(rawValue: defaultModel) != nil else {
                issues.append("models")
                return issues
            }
            guard key == ConfigSchema.Models.audioLLM else { continue }
            if let extraModels = section[ConfigSchema.Models.extraModels] {
                guard let values = extraModels as? [String],
                      values.allSatisfy({ AllowedSpeechModel(rawValue: $0) != nil }) else {
                    issues.append("models")
                    return issues
                }
            }
        }
        guard let systemASR = object[ConfigSchema.Root.systemASR] as? [String: Any],
              let engine = systemASR[ConfigSchema.SystemASR.engine] as? String,
              SystemASREngine(rawValue: engine) != nil else {
            issues.append("system_asr")
            return issues
        }
        if systemASR[ConfigSchema.SystemASR.deprecatedAllowAppleServerRecognition] != nil {
            issues.append("system_asr_deprecated")
        }
        if let hints = systemASR[ConfigSchema.SystemASR.keywordHintsEnabled], !(hints is Bool) {
            issues.append("system_asr")
            return issues
        }
        if hasInvalidExternalASRFields(systemASR[ConfigSchema.SystemASR.externalASR]) {
            issues.append("system_asr")
            return issues
        }
        if containsDeprecatedCustomMetadata(object[ConfigSchema.Root.customStyles] as? [String: Any]) {
            issues.append("custom_styles_deprecated")
        }
        if containsDeprecatedKeywordMetadata(object[ConfigSchema.Root.keywordGroups] as? [String: Any]) {
            issues.append("keyword_groups_deprecated")
        }
        guard let latency = object[ConfigSchema.Root.latency] as? [String: Any],
              latency[ConfigSchema.Latency.enabled] is Bool else {
            issues.append("latency")
            return issues
        }
        if !(latency[ConfigSchema.Latency.intervalSeconds] is NSNull) {
            guard let seconds = latency[ConfigSchema.Latency.intervalSeconds] as? Int,
                  ConfigLatencyInterval(rawValue: seconds) != nil else {
                issues.append("latency_interval")
                return issues
            }
        }
        if hasInvalidPreferenceFields(object[ConfigSchema.Root.preferences] as? [String: Any]) {
            issues.append("preferences")
        }
        return issues
    }

    func preferredWriteLanguage(fallback: UILanguage) -> UILanguage {
        guard let object = readJSONObject(url: configFileURL),
              let mergedObject = mergedConfigObject(from: object, fallbackLanguage: fallback) else {
            return fallback
        }
        let preferences = parsePreferences(
            mergedObject[ConfigSchema.Root.preferences] as? [String: Any],
            selectedModel: parseModelCatalogs(mergedObject[ConfigSchema.Root.models] as? [String: Any]).inputAudioDefaultModel
        )
        return preferences.uiLanguage
    }

    func containsDeprecatedCustomMetadata(_ rawStyles: [String: Any]?) -> Bool {
        guard let rawStyles else { return false }
        return rawStyles.values.contains { value in
            guard let object = value as? [String: Any] else { return false }
            return containsDeprecatedDisplayMetadata(object)
        }
    }

    func containsDeprecatedKeywordMetadata(_ rawGroups: [String: Any]?) -> Bool {
        guard let rawGroups else { return false }
        return rawGroups.values.contains { value in
            guard let object = value as? [String: Any] else { return false }
            return containsDeprecatedDisplayMetadata(object)
        }
    }

    func containsDeprecatedDisplayMetadata(_ object: [String: Any]) -> Bool {
        ConfigSchema.deprecatedDisplayMetadataKeys.contains { object[$0] != nil }
    }

    func containsDeprecatedTextLLMExtraModels(_ object: [String: Any]) -> Bool {
        guard let models = object[ConfigSchema.Root.models] as? [String: Any],
              let textLLM = models[ConfigSchema.Models.textLLM] as? [String: Any] else {
            return false
        }
        return textLLM[ConfigSchema.Models.extraModels] != nil
    }

    func hasInvalidExternalASRFields(_ value: Any?) -> Bool {
        guard let value else { return false }
        guard let object = value as? [String: Any] else { return true }
        guard let providerID = object[ConfigSchema.ExternalASR.providerID] else { return false }
        guard let raw = providerID as? String else { return true }
        guard let sanitized = raw.nilIfBlank else { return false }
        return !ExternalASRSettings.isValidProviderID(sanitized)
    }

    func hasInvalidPreferenceFields(_ object: [String: Any]?) -> Bool {
        guard let object else { return false }
        if let value = object[ConfigSchema.Preferences.uiLanguage], !isValidRawString(value, using: UILanguage.init(rawValue:)) {
            return true
        }
        if let value = object[ConfigSchema.Preferences.transcriptionStyle], !isValidTranscriptionStyleValue(value) {
            return true
        }
        if let value = object[ConfigSchema.Preferences.triggerKey], !isValidRawString(value, using: triggerKey(for:)) {
            return true
        }
        if let value = object[ConfigSchema.Preferences.keywordHintsEnabled], !(value is Bool) {
            return true
        }
        if let value = object[ConfigSchema.Preferences.enabledKeywordGroups], !isValidKeywordGroupIDList(value) {
            return true
        }
        if let value = object[ConfigSchema.Preferences.minRecordingDurationMS], !isValidRawInt(value, using: MinRecordingDuration.init(rawValue:)) {
            return true
        }
        if let value = object[ConfigSchema.Preferences.maxRecordingDurationSeconds], !isValidRawInt(value, using: MaxRecordingDuration.init(rawValue:)) {
            return true
        }
        if let value = object[ConfigSchema.Preferences.autoInsert], !(value is Bool) {
            return true
        }
        if let value = object[ConfigSchema.Preferences.launchAtLogin], !(value is Bool) {
            return true
        }
        if let trigger = object[ConfigSchema.Preferences.trigger], !(trigger is [String: Any]) {
            return true
        }
        if let trigger = object[ConfigSchema.Preferences.trigger] as? [String: Any],
           let value = trigger[ConfigSchema.Trigger.continuousRecordingDoubleTapEnabled],
           !(value is Bool) {
            return true
        }
        if let hud = object[ConfigSchema.Preferences.hud], !(hud is [String: Any]) {
            return true
        }
        guard let hud = object[ConfigSchema.Preferences.hud] as? [String: Any] else { return false }
        if let value = hud[ConfigSchema.HUD.visualStyle], !isValidRawString(value, using: HUDVisualStyle.init(rawValue:)) {
            return true
        }
        if let value = hud[ConfigSchema.HUD.messageDurationSeconds], !isValidRawInt(value, using: HUDMessageDuration.init(rawValue:)) {
            return true
        }
        if let value = hud[ConfigSchema.HUD.revealDelayMS], !isValidRawInt(value, using: HUDRevealDelay.init(rawValue:)) {
            return true
        }
        if let value = hud[ConfigSchema.HUD.liveASRPreviewEnabled], !(value is Bool) {
            return true
        }
        return false
    }

    private func isValidRawString<T>(_ value: Any, using transform: (String) -> T?) -> Bool {
        guard let raw = value as? String else { return false }
        return transform(raw) != nil
    }

    private func isValidRawInt<T>(_ value: Any, using transform: (Int) -> T?) -> Bool {
        guard let raw = value as? Int else { return false }
        return transform(raw) != nil
    }

    private func triggerKey(for raw: String) -> TriggerKey? {
        TriggerKey.allCandidates.first(where: { $0.identifier == raw })
    }

    private func isValidTranscriptionStyleValue(_ value: Any) -> Bool {
        guard let raw = (value as? String)?.nilIfBlank else { return false }
        let selection = TranscriptionStyleSelection(rawValue: raw)
        if selection.builtInStyle != nil {
            return true
        }
        guard raw.hasPrefix(TranscriptionStyleSelection.customPrefix) else { return false }
        return CustomTranscriptionStyleValidator.isValidID(
            String(raw.dropFirst(TranscriptionStyleSelection.customPrefix.count))
        )
    }

    private func isValidKeywordGroupIDList(_ value: Any) -> Bool {
        guard let ids = value as? [String] else { return false }
        return ids.allSatisfy(KeywordGroupValidator.isValidID)
    }
}
