import Foundation

extension ConfigLoader {
    func parse(object: [String: Any], source: ConfigSource, warnings: [String]) -> MimoConfig {
        let modelCatalogs = parseModelCatalogs(object[ConfigSchema.Root.models] as? [String: Any])
        let pipelineMode = parsePipelineMode(object[ConfigSchema.Root.transcriptionPipeline] as? [String: Any])
        let systemASRSettings = parseSystemASRSettings(object[ConfigSchema.Root.systemASR] as? [String: Any])
        let inputAudioDefaultModel = modelCatalogs.inputAudioDefaultModel
        let latencySettings = parseLatencySettings(object[ConfigSchema.Root.latency] as? [String: Any])
        let sources = parseSources(object: object)
        let customStyles = parseCustomStyles(object[ConfigSchema.Root.customStyles] as? [String: Any])
        let keywordParse = parseKeywordGroups(object[ConfigSchema.Root.keywordGroups] as? [String: Any])
        let preferences = parsePreferences(object[ConfigSchema.Root.preferences] as? [String: Any], selectedModel: inputAudioDefaultModel)
        let activeID = (object[ConfigSchema.Root.activeSource] as? String)?.nilIfBlank
            ?? MimoConfig.autoSourceID
        let modelSelection = PipelineModelSelectionPlanner.selection(
            mode: pipelineMode,
            catalogs: modelCatalogs
        )
        let selected = APISourceResolver.resolvedSource(
            activeSourceID: activeID,
            sources: sources,
            latencyResults: [:],
            modelCatalog: modelSelection.modelCatalog,
            requiredModel: modelSelection.selectedModel,
            mode: pipelineMode
        )
        var outputWarnings = warnings + keywordParse.warnings
        if preferences.keywordHintsEnabled {
            let enabledIDs = Set(preferences.enabledKeywordGroupIDs)
            let enabledKeywordCount = keywordParse.groups
                .filter { enabledIDs.contains($0.id) }
                .reduce(0) { $0 + $1.keywords.count }
            if enabledKeywordCount > KeywordGroupValidator.maxTotalKeywords {
                outputWarnings.append(ConfigWarning.raw(.keywordHintsTotalLimitExceeded))
            }
        }
        if object[ConfigSchema.Root.sources] == nil, pipelineMode.requiresModelAPI {
            outputWarnings.append(ConfigWarning.raw(.mustUseSources))
        }
        if object[ConfigSchema.Root.preferences] == nil {
            outputWarnings.append(ConfigWarning.raw(.missingPreferences))
        }
        if activeID == MimoConfig.autoSourceID {
            // Auto is resolved after latency checks; use the first source until measurements arrive.
        } else if sources.first(where: { $0.id == activeID }) == nil, !sources.isEmpty {
            outputWarnings.append(ConfigWarning.raw(.activeSourceMissing))
        }
        if pipelineMode == .systemASROnly {
            let fallbackSource = selected ?? sources.first
            return MimoConfig(
                baseURL: fallbackSource?.baseURL ?? MimoConfig.defaultBaseURL,
                apiKey: fallbackSource?.apiKey,
                source: source,
                activeSourceID: activeID,
                resolvedSourceID: fallbackSource?.id ?? activeID,
                sources: sources,
                modelCatalogs: modelCatalogs,
                pipelineMode: pipelineMode,
                systemASRSettings: systemASRSettings,
                customStyles: customStyles,
                keywordGroups: keywordParse.groups,
                latencySettings: latencySettings,
                preferences: preferences,
                warnings: outputWarnings
            )
        }
        guard let selected else {
            return MimoConfig(
                source: .missing,
                modelCatalogs: modelCatalogs,
                pipelineMode: pipelineMode,
                systemASRSettings: systemASRSettings,
                customStyles: customStyles,
                keywordGroups: keywordParse.groups,
                latencySettings: latencySettings,
                preferences: preferences,
                warnings: outputWarnings + [ConfigWarning.raw(.needsAtLeastOneSource)]
            )
        }
        return MimoConfig(
            baseURL: selected.baseURL,
            apiKey: selected.apiKey,
            source: source,
            activeSourceID: activeID,
            resolvedSourceID: selected.id,
            sources: sources,
            modelCatalogs: modelCatalogs,
            pipelineMode: pipelineMode,
            systemASRSettings: systemASRSettings,
            customStyles: customStyles,
            keywordGroups: keywordParse.groups,
            latencySettings: latencySettings,
            preferences: preferences,
            warnings: outputWarnings
        )
    }

    func parseSources(object: [String: Any]) -> [MimoConfigSource] {
        guard let rawSources = object[ConfigSchema.Root.sources] as? [String: Any] else {
            return []
        }
        return rawSources.compactMap { id, value in
                guard id.nilIfBlank != nil, id != MimoConfig.autoSourceID else { return nil }
                guard let sourceObject = value as? [String: Any] else { return nil }
                let baseURLText = sourceObject[ConfigSchema.Source.baseURL] as? String
                let baseURL = MimoConfig.normalizedBaseURL(from: baseURLText) ?? MimoConfig.defaultBaseURL
                return MimoConfigSource(
                    id: id,
                    baseURL: baseURL,
                    apiKey: sourceObject[ConfigSchema.Source.apiKey] as? String
                )
        }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    func parseModelCatalogs(
        _ rawModels: [String: Any]?
    ) -> ModelCatalogs {
        let inputAudio = rawModels?[ConfigSchema.Models.audioLLM] as? [String: Any]
        let textLLM = rawModels?[ConfigSchema.Models.textLLM] as? [String: Any]
        let inputAudioExtra = parseModelList(inputAudio?[ConfigSchema.Models.extraModels]) ?? AllowedSpeechModel.seededInputAudioModels
        let inputCandidate = (inputAudio?[ConfigSchema.Models.defaultModel] as? String).flatMap(AllowedSpeechModel.init(rawValue:)) ?? .defaultInputAudioModel
        let textCandidate = (textLLM?[ConfigSchema.Models.defaultModel] as? String).flatMap(AllowedSpeechModel.init(rawValue:)) ?? .defaultTextLLMModel
        let inputCatalog = AllowedSpeechModel.merged([inputCandidate] + AllowedSpeechModel.catalog(inputAudioExtra: inputAudioExtra))
        let inputDefault = AllowedSpeechModel.safeSelection(
            inputAudio?[ConfigSchema.Models.defaultModel] as? String,
            fallback: .defaultInputAudioModel,
            catalog: inputCatalog
        )
        let textDefault = textCandidate
        return ModelCatalogs(
            inputAudioDefaultModel: inputDefault,
            inputAudioExtraModels: inputAudioExtra,
            textLLMDefaultModel: textDefault
        )
    }

    func parseModelList(_ raw: Any?) -> [AllowedSpeechModel]? {
        guard let values = raw as? [String] else { return nil }
        return AllowedSpeechModel.merged(values.compactMap(AllowedSpeechModel.init(rawValue:)))
    }

    func parsePipelineMode(_ object: [String: Any]?) -> TranscriptionPipelineMode {
        guard let raw = object?[ConfigSchema.Pipeline.mode] as? String,
              let mode = TranscriptionPipelineMode(rawValue: raw) else {
            return .defaultMode
        }
        return mode
    }

    func parseSystemASRSettings(_ object: [String: Any]?) -> SystemASRSettings {
        let engine = (object?[ConfigSchema.SystemASR.engine] as? String).flatMap(SystemASREngine.init(rawValue:)) ?? .defaultEngine
        return SystemASRSettings(
            engine: engine,
            keywordHintsEnabled: object?[ConfigSchema.SystemASR.keywordHintsEnabled] as? Bool ?? true
        )
    }

    func parseCustomStyles(_ rawStyles: [String: Any]?) -> [CustomTranscriptionStyle] {
        guard let rawStyles else { return [] }
        return rawStyles.compactMap { id, value in
            guard CustomTranscriptionStyleValidator.isValidID(id),
                  let object = value as? [String: Any] else { return nil }
            let prompt = customPrompt(from: object)
            guard CustomTranscriptionStyleValidator.isValidPrompt(prompt) else { return nil }
            let displayName = (object[ConfigSchema.CustomStyle.displayName] as? String)?.nilIfBlank ?? id
            return CustomTranscriptionStyle(
                id: id,
                displayName: displayName,
                prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    func parseKeywordGroups(_ rawGroups: [String: Any]?) -> (groups: [KeywordGroup], warnings: [String]) {
        guard let rawGroups else { return ([], []) }
        var warnings: [String] = []
        var invalidGroupSeen = false
        var invalidKeywordSeen = false
        var groupLimitSeen = false

        let groups = rawGroups.compactMap { id, value -> KeywordGroup? in
            guard KeywordGroupValidator.isValidID(id),
                  let object = value as? [String: Any],
                  let rawKeywords = object[ConfigSchema.KeywordGroup.keywords] as? [Any] else {
                invalidGroupSeen = true
                return nil
            }

            var keywords: [String] = []
            for rawKeyword in rawKeywords {
                guard let keyword = rawKeyword as? String,
                      let sanitized = KeywordGroupValidator.sanitizedKeyword(keyword) else {
                    invalidKeywordSeen = true
                    continue
                }
                if !keywords.contains(sanitized) {
                    keywords.append(sanitized)
                }
            }
            guard !keywords.isEmpty else {
                invalidKeywordSeen = true
                return nil
            }
            if keywords.count > KeywordGroupValidator.maxKeywordsPerGroup {
                groupLimitSeen = true
                keywords = Array(keywords.prefix(KeywordGroupValidator.maxKeywordsPerGroup))
            }

            let displayName = (object[ConfigSchema.KeywordGroup.displayName] as? String)?.nilIfBlank
            return KeywordGroup(
                id: id,
                displayName: displayName,
                keywords: keywords
            )
        }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }

        if invalidGroupSeen {
            warnings.append(ConfigWarning.raw(.invalidKeywordGroupsIgnored))
        }
        if invalidKeywordSeen {
            warnings.append(ConfigWarning.raw(.invalidKeywordsIgnored))
        }
        if groupLimitSeen {
            warnings.append(ConfigWarning.raw(.keywordGroupLimitExceeded))
        }
        return (groups, warnings)
    }

    func customPrompt(from object: [String: Any]) -> String {
        if let prompt = object[ConfigSchema.CustomStyle.prompt] as? String {
            return prompt
        }
        if let lines = object[ConfigSchema.CustomStyle.promptLines] as? [String] {
            return lines.joined(separator: "\n")
        }
        return ""
    }

    func parseLatencySettings(_ object: [String: Any]?) -> ConfigLatencySettings {
        guard let object else { return .defaultSettings }
        if let enabled = object[ConfigSchema.Latency.enabled] as? Bool, !enabled {
            return ConfigLatencySettings(interval: .off)
        }
        if object[ConfigSchema.Latency.intervalSeconds] is NSNull {
            return ConfigLatencySettings(interval: .startupOnly)
        }
        guard let seconds = object[ConfigSchema.Latency.intervalSeconds] as? Int else {
            return .defaultSettings
        }
        return ConfigLatencySettings(interval: ConfigLatencyInterval.safeSelection(seconds))
    }

    func parsePreferences(_ object: [String: Any]?, selectedModel: AllowedSpeechModel) -> ConfigPreferences {
        let defaults = ConfigPreferences.defaultPreferences(selectedModel: selectedModel)
        guard let object else { return defaults }
        let hud = object[ConfigSchema.Preferences.hud] as? [String: Any]
        let trigger = object[ConfigSchema.Preferences.trigger] as? [String: Any]
        let styleRaw = (object[ConfigSchema.Preferences.transcriptionStyle] as? String)?.nilIfBlank
            ?? defaults.transcriptionStyleSelection.rawValue
        let selection = sanitizedStyleSelection(styleRaw, fallback: defaults.transcriptionStyleSelection)
        let enabledKeywordGroupIDs = (object[ConfigSchema.Preferences.enabledKeywordGroups] as? [String] ?? defaults.enabledKeywordGroupIDs)
            .filter(KeywordGroupValidator.isValidID)
        let keywordHintsEnabled = object[ConfigSchema.Preferences.keywordHintsEnabled] as? Bool ?? !enabledKeywordGroupIDs.isEmpty
        let triggerRaw = (object[ConfigSchema.Preferences.triggerKey] as? String)?.nilIfBlank
            ?? defaults.triggerKey.identifier
        let triggerKey = TriggerKey.allCandidates.first(where: { $0.identifier == triggerRaw }) ?? defaults.triggerKey
        let minDuration = (object[ConfigSchema.Preferences.minRecordingDurationMS] as? Int)
            .flatMap(MinRecordingDuration.init(rawValue:)) ?? defaults.minRecordingDuration
        let maxDuration = (object[ConfigSchema.Preferences.maxRecordingDurationSeconds] as? Int)
            .flatMap(MaxRecordingDuration.init(rawValue:)) ?? defaults.maxRecordingDuration
        let hudVisualStyle = (hud?[ConfigSchema.HUD.visualStyle] as? String)
            .flatMap(HUDVisualStyle.init(rawValue:)) ?? defaults.hudVisualStyle
        let messageDuration = (hud?[ConfigSchema.HUD.messageDurationSeconds] as? Int)
            .flatMap(HUDMessageDuration.init(rawValue:)) ?? defaults.hudMessageDuration
        let revealDelay = (hud?[ConfigSchema.HUD.revealDelayMS] as? Int)
            .flatMap(HUDRevealDelay.init(rawValue:)) ?? defaults.hudRevealDelay

        return ConfigPreferences(
            selectedModel: selectedModel,
            uiLanguage: UILanguage(rawValue: object[ConfigSchema.Preferences.uiLanguage] as? String ?? "") ?? defaults.uiLanguage,
            transcriptionStyleSelection: selection,
            keywordHintsEnabled: keywordHintsEnabled,
            enabledKeywordGroupIDs: enabledKeywordGroupIDs,
            triggerKey: triggerKey,
            continuousRecordingDoubleTapEnabled: trigger?[ConfigSchema.Trigger.continuousRecordingDoubleTapEnabled] as? Bool
                ?? defaults.continuousRecordingDoubleTapEnabled,
            minRecordingDuration: minDuration,
            maxRecordingDuration: maxDuration,
            autoInsert: object[ConfigSchema.Preferences.autoInsert] as? Bool ?? defaults.autoInsert,
            launchAtLogin: object[ConfigSchema.Preferences.launchAtLogin] as? Bool ?? defaults.launchAtLogin,
            hudVisualStyle: hudVisualStyle,
            hudMessageDuration: messageDuration,
            hudRevealDelay: revealDelay,
            liveASRPreviewEnabled: hud?[ConfigSchema.HUD.liveASRPreviewEnabled] as? Bool ?? defaults.liveASRPreviewEnabled
        )
    }

    private func sanitizedStyleSelection(
        _ raw: String,
        fallback: TranscriptionStyleSelection
    ) -> TranscriptionStyleSelection {
        let selection = TranscriptionStyleSelection(rawValue: raw)
        if selection.builtInStyle != nil {
            return selection
        }
        if raw.hasPrefix(TranscriptionStyleSelection.customPrefix) {
            let customID = String(raw.dropFirst(TranscriptionStyleSelection.customPrefix.count))
            if CustomTranscriptionStyleValidator.isValidID(customID) {
                return selection
            }
        }
        return fallback
    }
}
