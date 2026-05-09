import Foundation

public enum ConfigTemplateBuilder {
    public static func template(uiLanguage: UILanguage) -> String {
        ConfigDocumentWriter.defaultDocument(uiLanguage: uiLanguage)
    }
}

public struct ConfigRedactedStatus: Equatable, Sendable {
    public let baseURLHost: String
    public let apiKeyConfigured: Bool
    public let apiKeyPreview: String
    public let defaultModel: AllowedSpeechModel
    public let source: ConfigSource
    public let activeSourceID: String
    public let resolvedSourceID: String
    public let inputAudioModel: AllowedSpeechModel
    public let textLLMModel: AllowedSpeechModel
    public let pipelineMode: TranscriptionPipelineMode
    public let warnings: [String]

    public var displayLines: [String] {
        var lines = [
            "Source: \(activeSourceID)",
            "Base URL: \(baseURLHost)",
            "API Key: \(apiKeyPreview)",
            "Input Audio Model: \(inputAudioModel.rawValue)",
            "Text LLM Model: \(textLLMModel.rawValue)",
            "Transcription Mode: \(pipelineMode.rawValue)",
            "Config Source: \(source.displayName)"
        ]
        lines.append(contentsOf: warnings)
        return lines
    }
}

public enum ConfigValidationLoadResult: Equatable, Sendable {
    case valid(MimoConfig)
    case invalid([String])
}

public struct ConfigLoader {
    public var configFileURL: URL
    public var fileManager: FileManager

    public init(
        configFileURL: URL = ConfigLoader.defaultConfigFileURL(),
        fileManager: FileManager = .default
    ) {
        self.configFileURL = configFileURL
        self.fileManager = fileManager
    }

    public static func defaultConfigFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/\(AppConstants.configDirectoryName)/config.jsonc")
    }

    public func load() -> MimoConfig {
        if let file = readFileConfig(url: configFileURL, source: .configFile) {
            return file
        }
        return MimoConfig(source: .missing, warnings: ["Config file missing"])
    }

    public func ensureValidConfig(uiLanguage: UILanguage) -> MimoConfig {
        if fileManager.fileExists(atPath: configFileURL.path),
           let rawObject = readJSONObject(url: configFileURL),
           let mergedObject = mergedConfigObject(from: rawObject, fallbackLanguage: uiLanguage),
           validationIssues(for: mergedObject, rawObject: rawObject).isEmpty,
           let file = readFileConfig(url: configFileURL, source: .configFile) {
            return file
        }

        let repairObject = readJSONObject(url: configFileURL)
        if fileManager.fileExists(atPath: configFileURL.path) {
            _ = backupExistingConfig()
        }
        let repaired = repairObject.flatMap { repairedConfig(from: $0, uiLanguage: uiLanguage) }
        let wrote = repaired.map { writeConfig($0, uiLanguage: $0.preferences.uiLanguage) }
            ?? writeDefaultConfig(uiLanguage: uiLanguage)
        guard wrote else {
            return load()
        }
        return load()
    }

    public func loadValidConfigWithoutRepair() -> ConfigValidationLoadResult {
        guard fileManager.fileExists(atPath: configFileURL.path) else {
            return .invalid(["missing"])
        }
        guard let object = readJSONObject(url: configFileURL) else {
            return .invalid(["unreadable"])
        }
        guard let mergedObject = mergedConfigObject(from: object, fallbackLanguage: preferredLanguage(from: object, fallback: .defaultLanguage)) else {
            return .invalid(["unreadable"])
        }
        let issues = validationIssues(for: mergedObject, rawObject: object)
        guard issues.isEmpty else {
            return .invalid(issues)
        }
        guard let config = readFileConfig(url: configFileURL, source: .configFile),
              config.source == .configFile else {
            return .invalid(["unreadable"])
        }
        return .valid(config)
    }

    @discardableResult
    public func exportCurrentConfigSnapshot(
        _ config: MimoConfig,
        uiLanguage: UILanguage,
        now: Date = Date()
    ) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let outputURL = configFileURL.deletingLastPathComponent()
            .appendingPathComponent("config.current-\(formatter.string(from: now)).jsonc")
        do {
            try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let text = ConfigDocumentWriter.document(config: config, uiLanguage: uiLanguage)
            try Data(text.utf8).write(to: outputURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: outputURL.path)
            return outputURL
        } catch {
            return nil
        }
    }

    @discardableResult
    public func backupExistingConfig(now: Date = Date()) -> URL? {
        guard fileManager.fileExists(atPath: configFileURL.path) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backupURL = configFileURL.deletingLastPathComponent()
            .appendingPathComponent("config.jsonc.bak-\(formatter.string(from: now))")
        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: configFileURL, to: backupURL)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
            return backupURL
        } catch {
            return nil
        }
    }

    @discardableResult
    public func saveActiveSource(_ activeSourceID: String, uiLanguage: UILanguage? = nil) -> Bool {
        let activeID = activeSourceID.nilIfBlank ?? MimoConfig.defaultSourceID
        guard activeID == MimoConfig.autoSourceID || ConfigSourceNameValidator.isValid(activeID) else { return false }
        let current = ensureValidConfig(uiLanguage: preferredWriteLanguage(fallback: uiLanguage ?? .defaultLanguage))
        guard activeID == MimoConfig.autoSourceID || current.sources.contains(where: { $0.id == activeID }) else {
            return false
        }
        let selected = APISourceResolver.resolvedSource(
            activeSourceID: activeID,
            sources: current.sources,
            latencyResults: [:],
            modelCatalog: current.selectedPipelineModelCatalog,
            requiredModel: current.selectedPipelineModel,
            mode: current.pipelineMode
        )
        let output = MimoConfig(
            baseURL: selected?.baseURL ?? current.baseURL,
            apiKey: selected?.apiKey ?? current.apiKey,
            defaultModel: current.defaultModel,
            source: .configFile,
            activeSourceID: activeID,
            resolvedSourceID: selected?.id ?? current.resolvedSourceID,
            sources: current.sources,
            modelCatalogs: current.modelCatalogs,
            pipelineMode: current.pipelineMode,
            systemASRSettings: current.systemASRSettings,
            customStyles: current.customStyles,
            keywordGroups: current.keywordGroups,
            latencySettings: current.latencySettings,
            preferences: current.preferences
        )
        return writeConfig(output, uiLanguage: output.preferences.uiLanguage)
    }

    @discardableResult
    public func createTemplateIfMissing(uiLanguage: UILanguage) -> Bool {
        guard !fileManager.fileExists(atPath: configFileURL.path) else {
            return true
        }
        return writeDefaultConfig(uiLanguage: uiLanguage)
    }

    @discardableResult
    public func saveLatencyInterval(_ interval: ConfigLatencyInterval, uiLanguage: UILanguage? = nil) -> Bool {
        let current = ensureValidConfig(uiLanguage: preferredWriteLanguage(fallback: uiLanguage ?? .defaultLanguage))
        let output = MimoConfig(
            baseURL: current.baseURL,
            apiKey: current.apiKey,
            defaultModel: current.defaultModel,
            source: .configFile,
            activeSourceID: current.activeSourceID,
            resolvedSourceID: current.resolvedSourceID,
            sources: current.sources,
            modelCatalogs: current.modelCatalogs,
            pipelineMode: current.pipelineMode,
            systemASRSettings: current.systemASRSettings,
            customStyles: current.customStyles,
            keywordGroups: current.keywordGroups,
            latencySettings: ConfigLatencySettings(interval: interval),
            preferences: current.preferences
        )
        return writeConfig(output, uiLanguage: output.preferences.uiLanguage)
    }

    @discardableResult
    public func savePreferences(_ preferences: ConfigPreferences) -> Bool {
        let current = ensureValidConfig(uiLanguage: preferences.uiLanguage)
        let output = MimoConfig(
            baseURL: current.baseURL,
            apiKey: current.apiKey,
            defaultModel: preferences.selectedModel,
            source: .configFile,
            activeSourceID: current.activeSourceID,
            resolvedSourceID: current.resolvedSourceID,
            sources: current.sources,
            modelCatalogs: current.modelCatalogs.with(inputAudioDefaultModel: preferences.selectedModel),
            pipelineMode: current.pipelineMode,
            systemASRSettings: current.systemASRSettings,
            customStyles: current.customStyles,
            keywordGroups: current.keywordGroups,
            latencySettings: current.latencySettings,
            preferences: preferences
        )
        return writeConfig(output, uiLanguage: preferences.uiLanguage)
    }

    @discardableResult
    public func saveModelAndPipelineSettings(
        inputAudioModel: AllowedSpeechModel,
        textLLMModel: AllowedSpeechModel,
        pipelineMode: TranscriptionPipelineMode,
        systemASRSettings: SystemASRSettings,
        activeSourceID: String? = nil,
        uiLanguage: UILanguage? = nil
    ) -> Bool {
        let current = ensureValidConfig(uiLanguage: preferredWriteLanguage(fallback: uiLanguage ?? .defaultLanguage))
        let activeID = activeSourceID?.nilIfBlank ?? current.activeSourceID
        let catalogs = current.modelCatalogs.with(
            inputAudioDefaultModel: inputAudioModel,
            textLLMDefaultModel: textLLMModel
        )
        let selectedModel: AllowedSpeechModel
        let selectedCatalog: [AllowedSpeechModel]
        switch pipelineMode {
        case .inputAudio:
            selectedModel = inputAudioModel
            selectedCatalog = catalogs.inputAudioModels
        case .systemASRTextLLM:
            selectedModel = textLLMModel
            selectedCatalog = [catalogs.textLLMDefaultModel]
        case .systemASROnly:
            selectedModel = inputAudioModel
            selectedCatalog = []
        }
        let selectedSource = APISourceResolver.resolvedSource(
            activeSourceID: activeID,
            sources: current.sources,
            latencyResults: [:],
            modelCatalog: selectedCatalog,
            requiredModel: selectedModel,
            mode: pipelineMode
        )
        let output = MimoConfig(
            baseURL: selectedSource?.baseURL ?? current.baseURL,
            apiKey: selectedSource?.apiKey ?? current.apiKey,
            defaultModel: inputAudioModel,
            source: .configFile,
            activeSourceID: activeID,
            resolvedSourceID: selectedSource?.id ?? current.resolvedSourceID,
            sources: current.sources,
            modelCatalogs: catalogs,
            pipelineMode: pipelineMode,
            systemASRSettings: systemASRSettings,
            customStyles: current.customStyles,
            keywordGroups: current.keywordGroups,
            latencySettings: current.latencySettings,
            preferences: current.preferences.with(selectedModel: inputAudioModel)
        )
        return writeConfig(output, uiLanguage: output.preferences.uiLanguage)
    }

    private func writeDefaultConfig(uiLanguage: UILanguage) -> Bool {
        writeString(ConfigTemplateBuilder.template(uiLanguage: uiLanguage))
    }

    private func writeConfig(_ config: MimoConfig, uiLanguage: UILanguage) -> Bool {
        writeString(ConfigDocumentWriter.document(config: config, uiLanguage: uiLanguage))
    }

    private func writeString(_ text: String) -> Bool {
        do {
            let directory = configFileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = Data(text.utf8)
            try data.write(to: configFileURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFileURL.path)
            return true
        } catch {
            return false
        }
    }

    private func readFileConfig(url: URL, source: ConfigSource) -> MimoConfig? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        var warnings: [String] = []
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard let object = readJSONObject(url: url),
                  let mergedObject = mergedConfigObject(from: object, fallbackLanguage: preferredLanguage(from: object, fallback: .defaultLanguage)) else {
                return MimoConfig(source: source, warnings: warnings + ["Config warning: config.jsonc could not be read"])
            }
            let parsed = parse(object: mergedObject, source: source, warnings: warnings)
            if parsed.apiKey?.nilIfBlank != nil,
               let permissions = attributes[.posixPermissions] as? NSNumber,
               permissions.intValue & 0o077 != 0 {
                warnings.append("Config warning: config.jsonc containing secrets should be chmod 600")
                return MimoConfig(
                    baseURL: parsed.baseURL,
                    apiKey: parsed.apiKey,
                    defaultModel: parsed.defaultModel,
                    source: parsed.source,
                    activeSourceID: parsed.activeSourceID,
                    resolvedSourceID: parsed.resolvedSourceID,
                    sources: parsed.sources,
                    modelCatalogs: parsed.modelCatalogs,
                    pipelineMode: parsed.pipelineMode,
                    systemASRSettings: parsed.systemASRSettings,
                    customStyles: parsed.customStyles,
                    keywordGroups: parsed.keywordGroups,
                    latencySettings: parsed.latencySettings,
                    preferences: parsed.preferences,
                    warnings: parsed.warnings + ["Config warning: config.jsonc containing secrets should be chmod 600"]
                )
            }
            return parsed
        } catch {
            return MimoConfig(source: source, warnings: warnings + ["Config warning: config.jsonc could not be read"])
        }
    }

    func parse(object: [String: Any], source: ConfigSource, warnings: [String]) -> MimoConfig {
        let modelCatalogs = parseModelCatalogs(object["models"] as? [String: Any])
        let pipelineMode = parsePipelineMode(object["transcription_pipeline"] as? [String: Any])
        let systemASRSettings = parseSystemASRSettings(object["system_asr"] as? [String: Any])
        let defaultModel = modelCatalogs.inputAudioDefaultModel
        let latencySettings = parseLatencySettings(object["latency"] as? [String: Any])
        let sources = parseSources(object: object)
        let customStyles = parseCustomStyles(object["custom_styles"] as? [String: Any])
        let keywordParse = parseKeywordGroups(object["keyword_groups"] as? [String: Any])
        let preferences = parsePreferences(object["preferences"] as? [String: Any], selectedModel: defaultModel)
            ?? .defaultPreferences(selectedModel: defaultModel)
        let activeID = (object["active_source"] as? String)?.nilIfBlank
            ?? MimoConfig.autoSourceID
        let selectedModel: AllowedSpeechModel
        let selectedCatalog: [AllowedSpeechModel]
        switch pipelineMode {
        case .inputAudio:
            selectedModel = modelCatalogs.inputAudioDefaultModel
            selectedCatalog = modelCatalogs.inputAudioModels
        case .systemASRTextLLM:
            selectedModel = modelCatalogs.textLLMDefaultModel
            selectedCatalog = [modelCatalogs.textLLMDefaultModel]
        case .systemASROnly:
            selectedModel = modelCatalogs.inputAudioDefaultModel
            selectedCatalog = []
        }
        let selected = APISourceResolver.resolvedSource(
            activeSourceID: activeID,
            sources: sources,
            latencyResults: [:],
            modelCatalog: selectedCatalog,
            requiredModel: selectedModel,
            mode: pipelineMode
        )
        var outputWarnings = warnings + keywordParse.warnings
        if preferences.keywordHintsEnabled {
            let enabledIDs = Set(preferences.enabledKeywordGroupIDs)
            let enabledKeywordCount = keywordParse.groups
                .filter { enabledIDs.contains($0.id) }
                .reduce(0) { $0 + $1.keywords.count }
            if enabledKeywordCount > KeywordGroupValidator.maxTotalKeywords {
                outputWarnings.append("Config warning: keyword hints exceed total limit")
            }
        }
        if object["sources"] == nil, pipelineMode.requiresModelAPI {
            outputWarnings.append("Config warning: config.jsonc must use sources")
        }
        if object["preferences"] == nil {
            outputWarnings.append("Config warning: config.jsonc must include preferences")
        }
        if activeID == MimoConfig.autoSourceID {
            // Auto is resolved after latency checks; use the first source until measurements arrive.
        } else if sources.first(where: { $0.id == activeID }) == nil, !sources.isEmpty {
            outputWarnings.append("Config warning: active source missing, using first source")
        }
        if pipelineMode == .systemASROnly {
            let fallbackSource = selected ?? sources.first
            return MimoConfig(
                baseURL: fallbackSource?.baseURL ?? MimoConfig.defaultBaseURL,
                apiKey: fallbackSource?.apiKey,
                defaultModel: defaultModel,
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
                warnings: outputWarnings + ["Config warning: config.jsonc needs at least one source"]
            )
        }
        return MimoConfig(
            baseURL: selected.baseURL,
            apiKey: selected.apiKey,
            defaultModel: defaultModel,
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
        guard let rawSources = object["sources"] as? [String: Any] else {
            return []
        }
        return rawSources.compactMap { id, value in
                guard id.nilIfBlank != nil, id != MimoConfig.autoSourceID else { return nil }
                guard let sourceObject = value as? [String: Any] else { return nil }
                let baseURLText = sourceObject["base_url"] as? String
                let baseURL = MimoConfig.normalizedBaseURL(from: baseURLText) ?? MimoConfig.defaultBaseURL
                return MimoConfigSource(
                    id: id,
                    baseURL: baseURL,
                    apiKey: sourceObject["api_key"] as? String
                )
        }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    func parseModelCatalogs(
        _ rawModels: [String: Any]?
    ) -> ModelCatalogs {
        let inputAudio = rawModels?["audio_llm"] as? [String: Any]
        let textLLM = rawModels?["text_llm"] as? [String: Any]
        let inputAudioExtra = parseModelList(inputAudio?["extra_models"]) ?? AllowedSpeechModel.seededInputAudioModels
        let inputCandidate = (inputAudio?["default_model"] as? String).flatMap(AllowedSpeechModel.init(rawValue:)) ?? .defaultInputAudioModel
        let textCandidate = (textLLM?["default_model"] as? String).flatMap(AllowedSpeechModel.init(rawValue:)) ?? .defaultTextLLMModel
        let inputCatalog = AllowedSpeechModel.merged([inputCandidate] + AllowedSpeechModel.catalog(inputAudioExtra: inputAudioExtra))
        let inputDefault = AllowedSpeechModel.safeSelection(
            inputAudio?["default_model"] as? String,
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
        guard let raw = object?["mode"] as? String,
              let mode = TranscriptionPipelineMode(rawValue: raw) else {
            return .defaultMode
        }
        return mode
    }

    func parseSystemASRSettings(_ object: [String: Any]?) -> SystemASRSettings {
        let engine = (object?["engine"] as? String).flatMap(SystemASREngine.init(rawValue:)) ?? .defaultEngine
        return SystemASRSettings(
            engine: engine,
            keywordHintsEnabled: object?["keyword_hints_enabled"] as? Bool ?? true
        )
    }

    func parseCustomStyles(_ rawStyles: [String: Any]?) -> [CustomTranscriptionStyle] {
        guard let rawStyles else { return [] }
        return rawStyles.compactMap { id, value in
            guard CustomTranscriptionStyleValidator.isValidID(id),
                  let object = value as? [String: Any] else { return nil }
            let prompt = customPrompt(from: object)
            guard CustomTranscriptionStyleValidator.isValidPrompt(prompt) else { return nil }
            let displayName = (object["display_name"] as? String)?.nilIfBlank ?? id
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
                  let rawKeywords = object["keywords"] as? [Any] else {
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

            let displayName = (object["display_name"] as? String)?.nilIfBlank
            return KeywordGroup(
                id: id,
                displayName: displayName,
                keywords: keywords
            )
        }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }

        if invalidGroupSeen {
            warnings.append("Config warning: invalid keyword groups ignored")
        }
        if invalidKeywordSeen {
            warnings.append("Config warning: invalid keywords ignored")
        }
        if groupLimitSeen {
            warnings.append("Config warning: keyword group limit exceeded")
        }
        return (groups, warnings)
    }

    func customPrompt(from object: [String: Any]) -> String {
        if let prompt = object["prompt"] as? String {
            return prompt
        }
        if let lines = object["prompt_lines"] as? [String] {
            return lines.joined(separator: "\n")
        }
        return ""
    }

    func parseLatencySettings(_ object: [String: Any]?) -> ConfigLatencySettings {
        guard let object else { return .defaultSettings }
        if let enabled = object["enabled"] as? Bool, !enabled {
            return ConfigLatencySettings(interval: .off)
        }
        if object["interval_seconds"] is NSNull {
            return ConfigLatencySettings(interval: .startupOnly)
        }
        guard let seconds = object["interval_seconds"] as? Int else {
            return .defaultSettings
        }
        return ConfigLatencySettings(interval: ConfigLatencyInterval.safeSelection(seconds))
    }

    func parsePreferences(_ object: [String: Any]?, selectedModel: AllowedSpeechModel) -> ConfigPreferences? {
        guard let object,
              let uiLanguage = UILanguage(rawValue: object["ui_language"] as? String ?? ""),
              let styleRaw = (object["transcription_style"] as? String)?.nilIfBlank,
              let triggerRaw = (object["trigger_key"] as? String)?.nilIfBlank,
              let triggerKey = TriggerKey.allCandidates.first(where: { $0.identifier == triggerRaw }),
              let minMilliseconds = object["min_recording_duration_ms"] as? Int,
              let minDuration = MinRecordingDuration(rawValue: minMilliseconds),
              let maxSeconds = object["max_recording_duration_seconds"] as? Int,
              let maxDuration = MaxRecordingDuration(rawValue: maxSeconds),
              let autoInsert = object["auto_insert"] as? Bool,
              let launchAtLogin = object["launch_at_login"] as? Bool,
              let hud = object["hud"] as? [String: Any],
              let hudVisualRaw = hud["visual_style"] as? String,
              let hudVisualStyle = HUDVisualStyle(rawValue: hudVisualRaw),
              let messageSeconds = hud["message_duration_seconds"] as? Int,
              let messageDuration = HUDMessageDuration(rawValue: messageSeconds),
              let revealMilliseconds = hud["reveal_delay_ms"] as? Int,
              let revealDelay = HUDRevealDelay(rawValue: revealMilliseconds) else {
            return nil
        }
        let liveASRPreviewEnabled = hud["live_asr_preview_enabled"] as? Bool ?? false
        let trigger = object["trigger"] as? [String: Any]
        let continuousRecordingDoubleTapEnabled = trigger?["continuous_recording_double_tap_enabled"] as? Bool ?? false
        let selection = TranscriptionStyleSelection(rawValue: styleRaw)
        guard selection.builtInStyle != nil ||
              (styleRaw.hasPrefix(TranscriptionStyleSelection.customPrefix) &&
               CustomTranscriptionStyleValidator.isValidID(String(styleRaw.dropFirst(TranscriptionStyleSelection.customPrefix.count)))) else {
            return nil
        }
        let enabledKeywordGroupIDs = (object["enabled_keyword_groups"] as? [String] ?? [])
            .filter(KeywordGroupValidator.isValidID)
        let keywordHintsEnabled = object["keyword_hints_enabled"] as? Bool ?? !enabledKeywordGroupIDs.isEmpty
        return ConfigPreferences(
            selectedModel: selectedModel,
            uiLanguage: uiLanguage,
            transcriptionStyleSelection: selection,
            keywordHintsEnabled: keywordHintsEnabled,
            enabledKeywordGroupIDs: enabledKeywordGroupIDs,
            triggerKey: triggerKey,
            continuousRecordingDoubleTapEnabled: continuousRecordingDoubleTapEnabled,
            minRecordingDuration: minDuration,
            maxRecordingDuration: maxDuration,
            autoInsert: autoInsert,
            launchAtLogin: launchAtLogin,
            hudVisualStyle: hudVisualStyle,
            hudMessageDuration: messageDuration,
            hudRevealDelay: revealDelay,
            liveASRPreviewEnabled: liveASRPreviewEnabled
        )
    }
}
