import Foundation

public struct MimoConfig: Equatable, Sendable {
    public static let defaultBaseURL = URL(string: "https://token-plan-cn.xiaomimimo.com")!
    public static let defaultSourceID = "default"
    public static let autoSourceID = "auto"

    public let baseURL: URL
    public let apiKey: String?
    public let source: ConfigSource
    public let activeSourceID: String
    public let resolvedSourceID: String
    public let sources: [MimoConfigSource]
    public let modelCatalogs: ModelCatalogs
    public let pipelineMode: TranscriptionPipelineMode
    public let systemASRSettings: SystemASRSettings
    public let customStyles: [CustomTranscriptionStyle]
    public let keywordGroups: [KeywordGroup]
    public let latencySettings: ConfigLatencySettings
    public let preferences: ConfigPreferences
    public let warnings: [String]

    public init(
        baseURL: URL = Self.defaultBaseURL,
        apiKey: String? = nil,
        source: ConfigSource = .configFile,
        activeSourceID: String = Self.defaultSourceID,
        resolvedSourceID: String? = nil,
        sources: [MimoConfigSource]? = nil,
        modelCatalogs: ModelCatalogs = .defaultCatalogs,
        pipelineMode: TranscriptionPipelineMode = .defaultMode,
        systemASRSettings: SystemASRSettings = .defaultSettings,
        customStyles: [CustomTranscriptionStyle] = [],
        keywordGroups: [KeywordGroup] = [],
        latencySettings: ConfigLatencySettings = .defaultSettings,
        preferences: ConfigPreferences? = nil,
        warnings: [String] = []
    ) {
        let normalized = baseURL.normalizedMimoBaseURL ?? baseURL
        self.baseURL = normalized
        self.apiKey = apiKey?.nilIfBlank
        self.source = source
        self.activeSourceID = activeSourceID.nilIfBlank ?? Self.defaultSourceID
        self.resolvedSourceID = resolvedSourceID?.nilIfBlank ?? self.activeSourceID
        self.sources = sources ?? [
            MimoConfigSource(id: self.resolvedSourceID, baseURL: normalized, apiKey: apiKey)
        ]
        self.modelCatalogs = modelCatalogs
        self.pipelineMode = pipelineMode
        self.systemASRSettings = systemASRSettings
        self.customStyles = customStyles
        self.keywordGroups = keywordGroups
        self.latencySettings = latencySettings
        self.preferences = preferences ?? ConfigPreferences.defaultPreferences(
            selectedModel: modelCatalogs.inputAudioDefaultModel
        )
        self.warnings = warnings
    }

    public var redactedStatus: ConfigRedactedStatus {
        ConfigRedactedStatus(
            baseURLHost: baseURL.host ?? baseURL.absoluteString,
            apiKeyConfigured: apiKey?.isEmpty == false,
            apiKeyPreview: Self.redactedAPIKey(apiKey),
            source: source,
            activeSourceID: activeSourceID,
            resolvedSourceID: resolvedSourceID,
            inputAudioModel: modelCatalogs.inputAudioDefaultModel,
            textLLMModel: modelCatalogs.textLLMDefaultModel,
            pipelineMode: pipelineMode,
            warnings: warnings
        )
    }

    public var sourceSummaries: [ConfigSourceSummary] {
        sources.map { source in
            ConfigSourceSummary(
                id: source.id,
                host: source.baseURL.host ?? source.baseURL.absoluteString,
                apiKeyConfigured: source.apiKey?.nilIfBlank != nil
            )
        }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    public var isAutoSourceSelection: Bool {
        activeSourceID == Self.autoSourceID
    }

    public var selectedPipelineModel: AllowedSpeechModel {
        switch pipelineMode {
        case .inputAudio, .systemASROnly:
            return modelCatalogs.inputAudioDefaultModel
        case .systemASRTextLLM:
            return modelCatalogs.textLLMDefaultModel
        }
    }

    public var selectedPipelineModelCatalog: [AllowedSpeechModel] {
        switch pipelineMode {
        case .inputAudio:
            return modelCatalogs.inputAudioModels
        case .systemASRTextLLM:
            return [modelCatalogs.textLLMDefaultModel]
        case .systemASROnly:
            return []
        }
    }

    public func selectingSource(_ id: String) -> MimoConfig? {
        guard let selected = APISourceResolver.resolvedSource(
            activeSourceID: id,
            sources: sources,
            latencyResults: [:],
            modelCatalog: selectedPipelineModelCatalog,
            requiredModel: selectedPipelineModel,
            mode: pipelineMode
        ) else { return nil }
        return updating(
            baseURL: selected.baseURL,
            apiKey: selected.apiKey,
            activeSourceID: id,
            resolvedSourceID: selected.id,
            preferences: preferences.with(selectedModel: modelCatalogs.inputAudioDefaultModel)
        )
    }

    public func resolvingSource(using latencyResults: [String: SourceLatencyMeasurement]) -> MimoConfig {
        guard let selected = APISourceResolver.resolvedSource(
            activeSourceID: activeSourceID,
            sources: sources,
            latencyResults: latencyResults,
            modelCatalog: selectedPipelineModelCatalog,
            requiredModel: selectedPipelineModel,
            mode: pipelineMode
        ) else {
            return self
        }
        return updating(
            baseURL: selected.baseURL,
            apiKey: selected.apiKey,
            resolvedSourceID: selected.id,
            preferences: preferences.with(selectedModel: modelCatalogs.inputAudioDefaultModel)
        )
    }

    public static func redactedAPIKey(_ value: String?) -> String {
        guard let value = value?.nilIfBlank else { return "missing" }
        if value.count <= 10 {
            return String(repeating: "•", count: min(6, max(4, value.count)))
        }
        return "\(value.prefix(5))…\(value.suffix(4))"
    }

    public static func normalizedBaseURL(from raw: String?) -> URL? {
        guard var text = raw?.nilIfBlank else { return nil }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              components.host?.nilIfBlank != nil else {
            return nil
        }
        let pathParts = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        if pathParts.last?.lowercased() == "v1" {
            components.path = pathParts.dropLast().isEmpty
                ? ""
                : "/" + pathParts.dropLast().joined(separator: "/")
        }
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

public struct MimoConfigSource: Equatable, Sendable {
    public let id: String
    public let baseURL: URL
    public let apiKey: String?

    public init(id: String, baseURL: URL, apiKey: String?) {
        self.id = id.nilIfBlank ?? MimoConfig.defaultSourceID
        self.baseURL = baseURL.normalizedMimoBaseURL ?? baseURL
        self.apiKey = apiKey?.nilIfBlank
    }
}

public struct ConfigSourceSummary: Equatable, Sendable {
    public let id: String
    public let host: String
    public let apiKeyConfigured: Bool

    public init(id: String, host: String, apiKeyConfigured: Bool) {
        self.id = id
        self.host = host
        self.apiKeyConfigured = apiKeyConfigured
    }
}

public enum ConfigSource: String, Equatable, Sendable {
    case configFile
    case missing

    public var displayName: String {
        switch self {
        case .configFile: return "config file"
        case .missing: return "missing"
        }
    }
}

public enum ConfigLatencyInterval: Int, CaseIterable, Codable, Sendable {
    case off = 0
    case startupOnly = -1
    case seconds30 = 30
    case minutes1 = 60
    case minutes2 = 120
    case minutes5 = 300
    case minutes15 = 900
    case minutes30 = 1800
    case minutes60 = 3600

    public static let defaultInterval: ConfigLatencyInterval = .minutes30
    public static let allCases: [ConfigLatencyInterval] = [
        .seconds30,
        .minutes1,
        .minutes2,
        .minutes5,
        .minutes15,
        .minutes30,
        .minutes60,
        .off,
        .startupOnly
    ]

    public var seconds: Int? {
        switch self {
        case .off, .startupOnly:
            return nil
        case .seconds30, .minutes1, .minutes2, .minutes5, .minutes15, .minutes30, .minutes60:
            return rawValue
        }
    }

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .startupOnly: return "Startup"
        case .seconds30: return "30s"
        case .minutes1: return "1m"
        case .minutes2: return "2m"
        case .minutes5: return "5m"
        case .minutes15: return "15m"
        case .minutes30: return "30m"
        case .minutes60: return "60m"
        }
    }

    public static func safeSelection(_ rawValue: Int) -> ConfigLatencyInterval {
        ConfigLatencyInterval(rawValue: rawValue) ?? .defaultInterval
    }
}

public struct ConfigLatencySettings: Equatable, Sendable {
    public static let defaultSettings = ConfigLatencySettings(interval: .minutes30)

    public let interval: ConfigLatencyInterval

    public init(interval: ConfigLatencyInterval) {
        self.interval = interval
    }
}

public struct ConfigPreferences: Equatable, Sendable {
    public static let defaultEnabledKeywordGroupIDs: [String] = []

    public let selectedModel: AllowedSpeechModel
    public let uiLanguage: UILanguage
    public let transcriptionStyleSelection: TranscriptionStyleSelection
    public let keywordHintsEnabled: Bool
    public let enabledKeywordGroupIDs: [String]
    public let triggerKey: TriggerKey
    public let continuousRecordingDoubleTapEnabled: Bool
    public let minRecordingDuration: MinRecordingDuration
    public let maxRecordingDuration: MaxRecordingDuration
    public let autoInsert: Bool
    public let launchAtLogin: Bool
    public let hudVisualStyle: HUDVisualStyle
    public let hudMessageDuration: HUDMessageDuration
    public let hudRevealDelay: HUDRevealDelay
    public let liveASRPreviewEnabled: Bool

    public init(
        selectedModel: AllowedSpeechModel,
        uiLanguage: UILanguage,
        transcriptionStyleSelection: TranscriptionStyleSelection,
        keywordHintsEnabled: Bool = false,
        enabledKeywordGroupIDs: [String] = [],
        triggerKey: TriggerKey,
        continuousRecordingDoubleTapEnabled: Bool = false,
        minRecordingDuration: MinRecordingDuration,
        maxRecordingDuration: MaxRecordingDuration,
        autoInsert: Bool,
        launchAtLogin: Bool,
        hudVisualStyle: HUDVisualStyle,
        hudMessageDuration: HUDMessageDuration,
        hudRevealDelay: HUDRevealDelay,
        liveASRPreviewEnabled: Bool = false
    ) {
        self.selectedModel = selectedModel
        self.uiLanguage = uiLanguage
        self.transcriptionStyleSelection = transcriptionStyleSelection
        var seenKeywordGroupIDs: Set<String> = []
        let sanitizedKeywordGroupIDs = enabledKeywordGroupIDs.filter { id in
            guard KeywordGroupValidator.isValidID(id), !seenKeywordGroupIDs.contains(id) else {
                return false
            }
            seenKeywordGroupIDs.insert(id)
            return true
        }
        let effectiveKeywordHintsEnabled = keywordHintsEnabled && !sanitizedKeywordGroupIDs.isEmpty
        self.keywordHintsEnabled = effectiveKeywordHintsEnabled
        self.enabledKeywordGroupIDs = effectiveKeywordHintsEnabled ? sanitizedKeywordGroupIDs : []
        self.triggerKey = triggerKey
        self.continuousRecordingDoubleTapEnabled = continuousRecordingDoubleTapEnabled
        self.minRecordingDuration = minRecordingDuration
        self.maxRecordingDuration = maxRecordingDuration
        self.autoInsert = autoInsert
        self.launchAtLogin = launchAtLogin
        self.hudVisualStyle = hudVisualStyle
        self.hudMessageDuration = hudMessageDuration
        self.hudRevealDelay = hudRevealDelay
        self.liveASRPreviewEnabled = liveASRPreviewEnabled
    }

    public static func defaultPreferences(
        selectedModel: AllowedSpeechModel = .defaultInputAudioModel,
        uiLanguage: UILanguage = .defaultLanguage
    ) -> ConfigPreferences {
        ConfigPreferences(
            selectedModel: selectedModel,
            uiLanguage: uiLanguage,
            transcriptionStyleSelection: .defaultSelection,
            keywordHintsEnabled: false,
            enabledKeywordGroupIDs: defaultEnabledKeywordGroupIDs,
            triggerKey: .defaultTrigger,
            continuousRecordingDoubleTapEnabled: false,
            minRecordingDuration: .defaultDuration,
            maxRecordingDuration: .defaultDuration,
            autoInsert: true,
            launchAtLogin: true,
            hudVisualStyle: .defaultStyle,
            hudMessageDuration: .defaultDuration,
            hudRevealDelay: .defaultDelay,
            liveASRPreviewEnabled: false
        )
    }

    public func with(selectedModel: AllowedSpeechModel? = nil, uiLanguage: UILanguage? = nil) -> ConfigPreferences {
        updating(selectedModel: selectedModel, uiLanguage: uiLanguage)
    }

    public func updating(
        selectedModel: AllowedSpeechModel? = nil,
        uiLanguage: UILanguage? = nil,
        transcriptionStyleSelection: TranscriptionStyleSelection? = nil,
        keywordHintsEnabled: Bool? = nil,
        enabledKeywordGroupIDs: [String]? = nil,
        triggerKey: TriggerKey? = nil,
        continuousRecordingDoubleTapEnabled: Bool? = nil,
        minRecordingDuration: MinRecordingDuration? = nil,
        maxRecordingDuration: MaxRecordingDuration? = nil,
        autoInsert: Bool? = nil,
        launchAtLogin: Bool? = nil,
        hudVisualStyle: HUDVisualStyle? = nil,
        hudMessageDuration: HUDMessageDuration? = nil,
        hudRevealDelay: HUDRevealDelay? = nil,
        liveASRPreviewEnabled: Bool? = nil
    ) -> ConfigPreferences {
        ConfigPreferences(
            selectedModel: selectedModel ?? self.selectedModel,
            uiLanguage: uiLanguage ?? self.uiLanguage,
            transcriptionStyleSelection: transcriptionStyleSelection ?? self.transcriptionStyleSelection,
            keywordHintsEnabled: keywordHintsEnabled ?? self.keywordHintsEnabled,
            enabledKeywordGroupIDs: enabledKeywordGroupIDs ?? self.enabledKeywordGroupIDs,
            triggerKey: triggerKey ?? self.triggerKey,
            continuousRecordingDoubleTapEnabled: continuousRecordingDoubleTapEnabled ?? self.continuousRecordingDoubleTapEnabled,
            minRecordingDuration: minRecordingDuration ?? self.minRecordingDuration,
            maxRecordingDuration: maxRecordingDuration ?? self.maxRecordingDuration,
            autoInsert: autoInsert ?? self.autoInsert,
            launchAtLogin: launchAtLogin ?? self.launchAtLogin,
            hudVisualStyle: hudVisualStyle ?? self.hudVisualStyle,
            hudMessageDuration: hudMessageDuration ?? self.hudMessageDuration,
            hudRevealDelay: hudRevealDelay ?? self.hudRevealDelay,
            liveASRPreviewEnabled: liveASRPreviewEnabled ?? self.liveASRPreviewEnabled
        )
    }
}

public enum ConfigSourceNameValidator {
    public static func isValid(_ value: String) -> Bool {
        IdentifierValidator.isValid(value, reservedValues: [MimoConfig.autoSourceID])
    }
}

public enum CustomTranscriptionStyleValidator {
    public static func isValidID(_ value: String) -> Bool {
        IdentifierValidator.isValid(
            value,
            reservedValues: [MimoConfig.autoSourceID],
            disallowedValues: Set(TranscriptionStyle.allCases.map(\.rawValue))
        )
    }

    public static func isValidPrompt(_ value: String) -> Bool {
        guard let prompt = value.nilIfBlank else { return false }
        return prompt.count <= 8_000
    }
}
