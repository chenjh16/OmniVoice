import Foundation

@MainActor
public final class AppConfigStore {
    public static let shared = AppConfigStore()

    private let loader: ConfigLoader
    public private(set) var config: MimoConfig

    public init(
        loader: ConfigLoader = ConfigLoader(),
        initialUILanguage: UILanguage = .defaultLanguage
    ) {
        self.loader = loader
        self.config = loader.ensureValidConfig(uiLanguage: initialUILanguage)
    }

    public var configFileURL: URL {
        loader.configFileURL
    }

    public var fileManager: FileManager {
        loader.fileManager
    }

    @discardableResult
    public func ensureValidConfig(uiLanguage: UILanguage) -> MimoConfig {
        config = loader.ensureValidConfig(uiLanguage: uiLanguage)
        return config
    }

    public func loadValidConfigWithoutRepair() -> ConfigValidationLoadResult {
        let result = loader.loadValidConfigWithoutRepair()
        if case .valid(let loaded) = result {
            config = loaded
        }
        return result
    }

    @discardableResult
    public func createTemplateIfMissing(uiLanguage: UILanguage) -> Bool {
        let didCreate = loader.createTemplateIfMissing(uiLanguage: uiLanguage)
        if didCreate {
            config = loader.load()
        }
        return didCreate
    }

    @discardableResult
    public func saveActiveSource(_ activeSourceID: String, uiLanguage: UILanguage? = nil) -> Bool {
        guard loader.saveActiveSource(activeSourceID, uiLanguage: uiLanguage) else {
            return false
        }
        config = loader.load()
        return true
    }

    @discardableResult
    public func saveLatencyInterval(_ interval: ConfigLatencyInterval, uiLanguage: UILanguage? = nil) -> Bool {
        guard loader.saveLatencyInterval(interval, uiLanguage: uiLanguage) else {
            return false
        }
        config = loader.load()
        return true
    }

    @discardableResult
    public func savePreferences(_ preferences: ConfigPreferences) -> Bool {
        guard loader.savePreferences(preferences) else {
            return false
        }
        config = loader.load()
        return true
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
        guard loader.saveModelAndPipelineSettings(
            inputAudioModel: inputAudioModel,
            textLLMModel: textLLMModel,
            pipelineMode: pipelineMode,
            systemASRSettings: systemASRSettings,
            activeSourceID: activeSourceID,
            uiLanguage: uiLanguage
        ) else {
            return false
        }
        config = loader.load()
        return true
    }

    @discardableResult
    public func exportCurrentConfigSnapshot(uiLanguage: UILanguage, now: Date = Date()) -> URL? {
        loader.exportCurrentConfigSnapshot(config, uiLanguage: uiLanguage, now: now)
    }

    public func serializedDocument(uiLanguage: UILanguage? = nil) -> String {
        ConfigDocumentWriter.document(config: config, uiLanguage: uiLanguage ?? config.preferences.uiLanguage)
    }

    public func replaceInMemory(with config: MimoConfig) {
        self.config = config
    }

    public func updatePreferencesInMemory(_ transform: (ConfigPreferences) -> ConfigPreferences) {
        replaceConfig(preferences: transform(config.preferences))
    }

    public func updateModelSettingsInMemory(
        inputAudioModel: AllowedSpeechModel? = nil,
        textLLMModel: AllowedSpeechModel? = nil,
        pipelineMode: TranscriptionPipelineMode? = nil,
        systemASRSettings: SystemASRSettings? = nil
    ) {
        let catalogs = config.modelCatalogs.with(
            inputAudioDefaultModel: inputAudioModel,
            textLLMDefaultModel: textLLMModel
        )
        replaceConfig(
            defaultModel: catalogs.inputAudioDefaultModel,
            modelCatalogs: catalogs,
            pipelineMode: pipelineMode ?? config.pipelineMode,
            systemASRSettings: systemASRSettings ?? config.systemASRSettings,
            preferences: config.preferences.with(selectedModel: catalogs.inputAudioDefaultModel)
        )
    }

    private func replaceConfig(
        defaultModel: AllowedSpeechModel? = nil,
        modelCatalogs: ModelCatalogs? = nil,
        pipelineMode: TranscriptionPipelineMode? = nil,
        systemASRSettings: SystemASRSettings? = nil,
        latencySettings: ConfigLatencySettings? = nil,
        preferences: ConfigPreferences? = nil
    ) {
        config = MimoConfig(
            baseURL: config.baseURL,
            apiKey: config.apiKey,
            defaultModel: defaultModel ?? config.defaultModel,
            source: config.source,
            activeSourceID: config.activeSourceID,
            resolvedSourceID: config.resolvedSourceID,
            sources: config.sources,
            modelCatalogs: modelCatalogs ?? config.modelCatalogs,
            pipelineMode: pipelineMode ?? config.pipelineMode,
            systemASRSettings: systemASRSettings ?? config.systemASRSettings,
            customStyles: config.customStyles,
            keywordGroups: config.keywordGroups,
            latencySettings: latencySettings ?? config.latencySettings,
            preferences: preferences ?? config.preferences,
            warnings: config.warnings
        )
    }
}
