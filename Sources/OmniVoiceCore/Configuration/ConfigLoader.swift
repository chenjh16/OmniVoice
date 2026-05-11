import Foundation

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
        return MimoConfig(source: .missing, warnings: [ConfigWarning.raw(.fileMissing)])
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
        let outputAPIKey: String? = {
            guard let selected else { return current.apiKey }
            return selected.apiKey
        }()
        let output = current.updating(
            baseURL: selected?.baseURL ?? current.baseURL,
            apiKey: outputAPIKey,
            source: .configFile,
            activeSourceID: activeID,
            resolvedSourceID: selected?.id ?? current.resolvedSourceID
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
        let output = current.updating(
            source: .configFile,
            latencySettings: ConfigLatencySettings(interval: interval)
        )
        return writeConfig(output, uiLanguage: output.preferences.uiLanguage)
    }

    @discardableResult
    public func savePreferences(_ preferences: ConfigPreferences) -> Bool {
        let current = ensureValidConfig(uiLanguage: preferences.uiLanguage)
        let output = current.updating(
            source: .configFile,
            modelCatalogs: current.modelCatalogs.with(inputAudioDefaultModel: preferences.selectedModel),
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
        let modelSelection = PipelineModelSelectionPlanner.selection(
            mode: pipelineMode,
            catalogs: catalogs,
            inputAudioModel: inputAudioModel,
            textLLMModel: textLLMModel
        )
        let selectedSource = APISourceResolver.resolvedSource(
            activeSourceID: activeID,
            sources: current.sources,
            latencyResults: [:],
            modelCatalog: modelSelection.modelCatalog,
            requiredModel: modelSelection.selectedModel,
            mode: pipelineMode
        )
        let outputAPIKey: String? = {
            guard let selectedSource else { return current.apiKey }
            return selectedSource.apiKey
        }()
        let output = current.updating(
            baseURL: selectedSource?.baseURL ?? current.baseURL,
            apiKey: outputAPIKey,
            source: .configFile,
            activeSourceID: activeID,
            resolvedSourceID: selectedSource?.id ?? current.resolvedSourceID,
            modelCatalogs: catalogs,
            pipelineMode: pipelineMode,
            systemASRSettings: systemASRSettings,
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
        let warnings: [String] = []
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard let object = readJSONObject(url: url),
                  let mergedObject = mergedConfigObject(from: object, fallbackLanguage: preferredLanguage(from: object, fallback: .defaultLanguage)) else {
                return MimoConfig(source: source, warnings: warnings + [ConfigWarning.raw(.unreadable)])
            }
            let parsed = parse(object: mergedObject, source: source, warnings: warnings)
            if parsed.apiKey?.nilIfBlank != nil,
               let permissions = attributes[.posixPermissions] as? NSNumber,
               permissions.intValue & 0o077 != 0 {
                return parsed.updating(warnings: parsed.warnings + [ConfigWarning.raw(.secretsFileMode)])
            }
            return parsed
        } catch {
            return MimoConfig(source: source, warnings: warnings + [ConfigWarning.raw(.unreadable)])
        }
    }

}
