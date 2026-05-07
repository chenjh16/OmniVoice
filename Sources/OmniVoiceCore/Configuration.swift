import Foundation

public struct MimoConfig: Equatable, Sendable {
    public static let defaultBaseURL = URL(string: "https://token-plan-sgp.xiaomimimo.com")!
    public static let defaultSourceID = "default"
    public static let autoSourceID = "auto"

    public let baseURL: URL
    public let apiKey: String?
    public let defaultModel: AllowedSpeechModel
    public let source: ConfigSource
    public let activeSourceID: String
    public let resolvedSourceID: String
    public let sources: [MimoConfigSource]
    public let customStyles: [CustomTranscriptionStyle]
    public let keywordGroups: [KeywordGroup]
    public let latencySettings: ConfigLatencySettings
    public let preferences: ConfigPreferences
    public let warnings: [String]

    public init(
        baseURL: URL = Self.defaultBaseURL,
        apiKey: String? = nil,
        defaultModel: AllowedSpeechModel = .defaultModel,
        source: ConfigSource = .configFile,
        activeSourceID: String = Self.defaultSourceID,
        resolvedSourceID: String? = nil,
        sources: [MimoConfigSource]? = nil,
        customStyles: [CustomTranscriptionStyle] = [],
        keywordGroups: [KeywordGroup] = [],
        latencySettings: ConfigLatencySettings = .defaultSettings,
        preferences: ConfigPreferences? = nil,
        warnings: [String] = []
    ) {
        let normalized = baseURL.normalizedMimoBaseURL ?? baseURL
        self.baseURL = normalized
        self.apiKey = apiKey?.nilIfBlank
        self.defaultModel = defaultModel
        self.source = source
        self.activeSourceID = activeSourceID.nilIfBlank ?? Self.defaultSourceID
        self.resolvedSourceID = resolvedSourceID?.nilIfBlank ?? self.activeSourceID
        self.sources = sources ?? [
            MimoConfigSource(id: self.resolvedSourceID, baseURL: normalized, apiKey: apiKey)
        ]
        self.customStyles = customStyles
        self.keywordGroups = keywordGroups
        self.latencySettings = latencySettings
        self.preferences = preferences ?? ConfigPreferences.defaultPreferences(selectedModel: defaultModel)
        self.warnings = warnings
    }

    public var redactedStatus: ConfigRedactedStatus {
        ConfigRedactedStatus(
            baseURLHost: baseURL.host ?? baseURL.absoluteString,
            apiKeyConfigured: apiKey?.isEmpty == false,
            apiKeyPreview: Self.redactedAPIKey(apiKey),
            defaultModel: defaultModel,
            source: source,
            activeSourceID: activeSourceID,
            resolvedSourceID: resolvedSourceID,
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

    public func selectingSource(_ id: String) -> MimoConfig? {
        guard let selected = APISourceResolver.resolvedSource(
            activeSourceID: id,
            sources: sources,
            latencyResults: [:]
        ) else { return nil }
        return MimoConfig(
            baseURL: selected.baseURL,
            apiKey: selected.apiKey,
            defaultModel: defaultModel,
            source: source,
            activeSourceID: id,
            resolvedSourceID: selected.id,
            sources: sources,
            customStyles: customStyles,
            keywordGroups: keywordGroups,
            latencySettings: latencySettings,
            preferences: preferences.with(selectedModel: defaultModel),
            warnings: warnings
        )
    }

    public func resolvingSource(using latencyResults: [String: SourceLatencyMeasurement]) -> MimoConfig {
        guard let selected = APISourceResolver.resolvedSource(
            activeSourceID: activeSourceID,
            sources: sources,
            latencyResults: latencyResults
        ) else {
            return self
        }
        return MimoConfig(
            baseURL: selected.baseURL,
            apiKey: selected.apiKey,
            defaultModel: defaultModel,
            source: source,
            activeSourceID: activeSourceID,
            resolvedSourceID: selected.id,
            sources: sources,
            customStyles: customStyles,
            keywordGroups: keywordGroups,
            latencySettings: latencySettings,
            preferences: preferences.with(selectedModel: defaultModel),
            warnings: warnings
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

public enum APISourceResolver {
    public static func resolvedSource(
        activeSourceID: String,
        sources: [MimoConfigSource],
        latencyResults: [String: SourceLatencyMeasurement]
    ) -> MimoConfigSource? {
        guard !sources.isEmpty else { return nil }
        let activeID = activeSourceID.nilIfBlank ?? MimoConfig.defaultSourceID
        guard activeID == MimoConfig.autoSourceID else {
            return sources.first(where: { $0.id == activeID }) ?? sources.first
        }

        let eligible = sources.compactMap { source -> (source: MimoConfigSource, measurement: SourceLatencyMeasurement)? in
            guard let measurement = latencyResults[source.id], measurement.isAutoEligible else { return nil }
            return (source, measurement)
        }
        return eligible.sorted {
            let leftMS = $0.measurement.milliseconds ?? Int.max
            let rightMS = $1.measurement.milliseconds ?? Int.max
            if leftMS != rightMS {
                return leftMS < rightMS
            }
            return $0.source.id.localizedStandardCompare($1.source.id) == .orderedAscending
        }.first?.source ?? sources.first
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
    public static let defaultEnabledKeywordGroupIDs = ["omnivoice_terms", "technical_terms"]

    public let selectedModel: AllowedSpeechModel
    public let uiLanguage: UILanguage
    public let transcriptionStyleSelection: TranscriptionStyleSelection
    public let keywordHintsEnabled: Bool
    public let enabledKeywordGroupIDs: [String]
    public let triggerKey: TriggerKey
    public let minRecordingDuration: MinRecordingDuration
    public let maxRecordingDuration: MaxRecordingDuration
    public let autoInsert: Bool
    public let launchAtLogin: Bool
    public let hudVisualStyle: HUDVisualStyle
    public let hudMessageDuration: HUDMessageDuration
    public let hudRevealDelay: HUDRevealDelay

    public init(
        selectedModel: AllowedSpeechModel,
        uiLanguage: UILanguage,
        transcriptionStyleSelection: TranscriptionStyleSelection,
        keywordHintsEnabled: Bool = true,
        enabledKeywordGroupIDs: [String] = [],
        triggerKey: TriggerKey,
        minRecordingDuration: MinRecordingDuration,
        maxRecordingDuration: MaxRecordingDuration,
        autoInsert: Bool,
        launchAtLogin: Bool,
        hudVisualStyle: HUDVisualStyle,
        hudMessageDuration: HUDMessageDuration,
        hudRevealDelay: HUDRevealDelay
    ) {
        self.selectedModel = selectedModel
        self.uiLanguage = uiLanguage
        self.transcriptionStyleSelection = transcriptionStyleSelection
        self.keywordHintsEnabled = keywordHintsEnabled
        self.enabledKeywordGroupIDs = enabledKeywordGroupIDs
        self.triggerKey = triggerKey
        self.minRecordingDuration = minRecordingDuration
        self.maxRecordingDuration = maxRecordingDuration
        self.autoInsert = autoInsert
        self.launchAtLogin = launchAtLogin
        self.hudVisualStyle = hudVisualStyle
        self.hudMessageDuration = hudMessageDuration
        self.hudRevealDelay = hudRevealDelay
    }

    public static func defaultPreferences(
        selectedModel: AllowedSpeechModel = .defaultModel,
        uiLanguage: UILanguage = .defaultLanguage
    ) -> ConfigPreferences {
        ConfigPreferences(
            selectedModel: selectedModel,
            uiLanguage: uiLanguage,
            transcriptionStyleSelection: .defaultSelection,
            keywordHintsEnabled: true,
            enabledKeywordGroupIDs: defaultEnabledKeywordGroupIDs,
            triggerKey: .defaultTrigger,
            minRecordingDuration: .defaultDuration,
            maxRecordingDuration: .defaultDuration,
            autoInsert: true,
            launchAtLogin: false,
            hudVisualStyle: .defaultStyle,
            hudMessageDuration: .defaultDuration,
            hudRevealDelay: .defaultDelay
        )
    }

    public func with(selectedModel: AllowedSpeechModel? = nil, uiLanguage: UILanguage? = nil) -> ConfigPreferences {
        ConfigPreferences(
            selectedModel: selectedModel ?? self.selectedModel,
            uiLanguage: uiLanguage ?? self.uiLanguage,
            transcriptionStyleSelection: transcriptionStyleSelection,
            keywordHintsEnabled: keywordHintsEnabled,
            enabledKeywordGroupIDs: enabledKeywordGroupIDs,
            triggerKey: triggerKey,
            minRecordingDuration: minRecordingDuration,
            maxRecordingDuration: maxRecordingDuration,
            autoInsert: autoInsert,
            launchAtLogin: launchAtLogin,
            hudVisualStyle: hudVisualStyle,
            hudMessageDuration: hudMessageDuration,
            hudRevealDelay: hudRevealDelay
        )
    }
}

public enum ConfigSourceNameValidator {
    public static func isValid(_ value: String) -> Bool {
        guard let trimmed = value.nilIfBlank,
              trimmed != MimoConfig.autoSourceID,
              trimmed.count <= 48 else {
            return false
        }
        return trimmed.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#,
            options: .regularExpression
        ) != nil
    }
}

public enum CustomTranscriptionStyleValidator {
    public static func isValidID(_ value: String) -> Bool {
        guard let trimmed = value.nilIfBlank,
              trimmed.count <= 48,
              !TranscriptionStyle.allCases.map(\.rawValue).contains(trimmed),
              trimmed != MimoConfig.autoSourceID else {
            return false
        }
        return trimmed.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#,
            options: .regularExpression
        ) != nil
    }

    public static func isValidPrompt(_ value: String) -> Bool {
        guard let prompt = value.nilIfBlank else { return false }
        return prompt.count <= 8_000
    }
}

public enum ConfigDocumentWriter {
    public static func defaultDocument(uiLanguage: UILanguage) -> String {
        document(config: defaultConfig(uiLanguage: uiLanguage), uiLanguage: uiLanguage)
    }

    public static func document(config: MimoConfig, uiLanguage: UILanguage) -> String {
        let text = ConfigDocumentText(language: uiLanguage)
        var lines: [String] = ["{"]

        addComment(text.fileIntro, indent: 2, to: &lines)
        addComment(text.activeSource, indent: 2, to: &lines)
        lines.append("  \"active_source\": \(jsonString(config.activeSourceID)),")
        addComment(text.defaultModel, indent: 2, to: &lines)
        lines.append("  \"default_model\": \(jsonString(config.defaultModel.rawValue)),")
        addComment(text.sources, indent: 2, to: &lines)
        lines.append("  \"sources\": {")
        let sources = config.sources.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        for (index, source) in sources.enumerated() {
            addComment(text.source(source.id), indent: 4, to: &lines)
            lines.append("    \(jsonString(source.id)): {")
            addComment(text.baseURL, indent: 6, to: &lines)
            lines.append("      \"base_url\": \(jsonString(source.baseURL.absoluteString)),")
            addComment(text.apiKey, indent: 6, to: &lines)
            lines.append("      \"api_key\": \(jsonString(source.apiKey ?? ""))")
            lines.append("    }\(index == sources.count - 1 ? "" : ",")")
        }
        lines.append("  },")

        addComment(text.latency, indent: 2, to: &lines)
        lines.append("  \"latency\": {")
        addComment(text.latencyEnabled, indent: 4, to: &lines)
        lines.append("    \"enabled\": \(config.latencySettings.interval == .off ? "false" : "true"),")
        addComment(text.latencyInterval, indent: 4, to: &lines)
        if let seconds = config.latencySettings.interval.seconds {
            lines.append("    \"interval_seconds\": \(seconds)")
        } else {
            lines.append("    \"interval_seconds\": null")
        }
        lines.append("  },")

        let preferences = config.preferences.with(selectedModel: config.defaultModel, uiLanguage: uiLanguage)
        addComment(text.preferences, indent: 2, to: &lines)
        lines.append("  \"preferences\": {")
        addComment(text.uiLanguage, indent: 4, to: &lines)
        lines.append("    \"ui_language\": \(jsonString(preferences.uiLanguage.rawValue)),")
        addComment(text.transcriptionStyle, indent: 4, to: &lines)
        lines.append("    \"transcription_style\": \(jsonString(preferences.transcriptionStyleSelection.rawValue)),")
        addComment(text.keywordHintsEnabled, indent: 4, to: &lines)
        lines.append("    \"keyword_hints_enabled\": \(preferences.keywordHintsEnabled ? "true" : "false"),")
        addComment(text.enabledKeywordGroups, indent: 4, to: &lines)
        lines.append("    \"enabled_keyword_groups\": \(jsonStringArray(preferences.enabledKeywordGroupIDs)),")
        addComment(text.triggerKey, indent: 4, to: &lines)
        lines.append("    \"trigger_key\": \(jsonString(preferences.triggerKey.identifier)),")
        addComment(text.minRecording, indent: 4, to: &lines)
        lines.append("    \"min_recording_duration_ms\": \(preferences.minRecordingDuration.rawValue),")
        addComment(text.maxRecording, indent: 4, to: &lines)
        lines.append("    \"max_recording_duration_seconds\": \(preferences.maxRecordingDuration.rawValue),")
        addComment(text.autoInsert, indent: 4, to: &lines)
        lines.append("    \"auto_insert\": \(preferences.autoInsert ? "true" : "false"),")
        addComment(text.launchAtLogin, indent: 4, to: &lines)
        lines.append("    \"launch_at_login\": \(preferences.launchAtLogin ? "true" : "false"),")
        addComment(text.hud, indent: 4, to: &lines)
        lines.append("    \"hud\": {")
        addComment(text.hudVisualStyle, indent: 6, to: &lines)
        lines.append("      \"visual_style\": \(jsonString(preferences.hudVisualStyle.rawValue)),")
        addComment(text.hudMessageDuration, indent: 6, to: &lines)
        lines.append("      \"message_duration_seconds\": \(preferences.hudMessageDuration.rawValue),")
        addComment(text.hudRevealDelay, indent: 6, to: &lines)
        lines.append("      \"reveal_delay_ms\": \(preferences.hudRevealDelay.rawValue)")
        lines.append("    }")
        lines.append("  },")

        addComment(text.customStyles, indent: 2, to: &lines)
        lines.append("  \"custom_styles\": {")
        let styles = config.customStyles.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        for (index, style) in styles.enumerated() {
            addComment(text.customStyle(style.id), indent: 4, to: &lines)
            lines.append("    \(jsonString(style.id)): {")
            addComment(text.customDisplayName, indent: 6, to: &lines)
            lines.append("      \"display_name\": \(jsonString(style.displayName)),")
            addComment(text.customDisplayNameZH, indent: 6, to: &lines)
            lines.append("      \"display_name_zh\": \(jsonString(style.displayNameZH ?? style.displayName)),")
            addComment(text.customDescription, indent: 6, to: &lines)
            lines.append("      \"description\": \(jsonString(style.description ?? "")),")
            addComment(text.customDescriptionZH, indent: 6, to: &lines)
            lines.append("      \"description_zh\": \(jsonString(style.descriptionZH ?? "")),")
            addComment(text.customPromptLines, indent: 6, to: &lines)
            lines.append("      \"prompt_lines\": [")
            let promptLines = style.prompt.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (lineIndex, promptLine) in promptLines.enumerated() {
                lines.append("        \(jsonString(promptLine))\(lineIndex == promptLines.count - 1 ? "" : ",")")
            }
            lines.append("      ]")
            lines.append("    }\(index == styles.count - 1 ? "" : ",")")
        }
        lines.append("  },")

        addComment(text.keywordGroups, indent: 2, to: &lines)
        lines.append("  \"keyword_groups\": {")
        let keywordGroups = config.keywordGroups.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        for (index, group) in keywordGroups.enumerated() {
            addComment(text.keywordGroup(group.id), indent: 4, to: &lines)
            lines.append("    \(jsonString(group.id)): {")
            addComment(text.keywordDisplayName, indent: 6, to: &lines)
            lines.append("      \"display_name\": \(jsonString(group.displayName ?? group.displayNameZH ?? group.id)),")
            if let description = group.description ?? group.descriptionZH {
                addComment(text.keywordDescription, indent: 6, to: &lines)
                lines.append("      \"description\": \(jsonString(description)),")
            }
            addComment(text.keywords, indent: 6, to: &lines)
            lines.append("      \"keywords\": [")
            for (keywordIndex, keyword) in group.keywords.enumerated() {
                lines.append("        \(jsonString(keyword))\(keywordIndex == group.keywords.count - 1 ? "" : ",")")
            }
            lines.append("      ]")
            lines.append("    }\(index == keywordGroups.count - 1 ? "" : ",")")
        }
        lines.append("  }")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func defaultConfig(uiLanguage: UILanguage) -> MimoConfig {
        let source = MimoConfigSource(
            id: "config1",
            baseURL: MimoConfig.defaultBaseURL,
            apiKey: ""
        )
        return MimoConfig(
            baseURL: source.baseURL,
            apiKey: nil,
            defaultModel: .defaultModel,
            source: .configFile,
            activeSourceID: MimoConfig.autoSourceID,
            resolvedSourceID: source.id,
            sources: [source],
            customStyles: [defaultCustomStyle(uiLanguage: uiLanguage)],
            keywordGroups: defaultKeywordGroups(uiLanguage: uiLanguage),
            latencySettings: .defaultSettings,
            preferences: .defaultPreferences(selectedModel: .defaultModel, uiLanguage: uiLanguage)
        )
    }

    private static func defaultKeywordGroups(uiLanguage: UILanguage) -> [KeywordGroup] {
        switch uiLanguage {
        case .chinese:
            return [
                KeywordGroup(
                    id: "omnivoice_terms",
                    displayName: "OmniVoice 术语",
                    description: "项目和 API 相关术语。",
                    keywords: ["OmniVoice", "MiMo", "mimo-v2-omni", "config.jsonc", "ActionPanel", "HUD", "Panel"]
                ),
                KeywordGroup(
                    id: "technical_terms",
                    displayName: "技术术语",
                    description: "代码、命令和 macOS 相关术语。",
                    keywords: ["Swift", "AppKit", "macOS", "JSONC", "API", "make run", "Cmd+V", "Fn"]
                )
            ]
        case .english:
            return [
                KeywordGroup(
                    id: "omnivoice_terms",
                    displayName: "OmniVoice Terms",
                    description: "Project and API vocabulary.",
                    keywords: ["OmniVoice", "MiMo", "mimo-v2-omni", "config.jsonc", "ActionPanel", "HUD", "Panel"]
                ),
                KeywordGroup(
                    id: "technical_terms",
                    displayName: "Technical Terms",
                    description: "Code, command, and macOS vocabulary.",
                    keywords: ["Swift", "AppKit", "macOS", "JSONC", "API", "make run", "Cmd+V", "Fn"]
                )
            ]
        }
    }

    private static func defaultCustomStyle(uiLanguage: UILanguage) -> CustomTranscriptionStyle {
        switch uiLanguage {
        case .chinese:
            return CustomTranscriptionStyle(
                id: "meeting_notes",
                displayName: "Meeting Notes",
                displayNameZH: "会议纪要",
                description: "Turn speech into concise meeting notes.",
                descriptionZH: "把口述整理成简洁会议纪要。",
                prompt: [
                    "请把这段音频整理成简洁会议纪要。",
                    "保留明确说出的决定、待办、时间、人名、项目名和技术词。",
                    "如果有多个要点，使用简短的换行列表。",
                    "不要新增用户没有说出的事实、结论、负责人或截止日期。"
                ].joined(separator: "\n")
            )
        case .english:
            return CustomTranscriptionStyle(
                id: "meeting_notes",
                displayName: "Meeting Notes",
                displayNameZH: "会议纪要",
                description: "Turn speech into concise meeting notes.",
                descriptionZH: "把口述整理成简洁会议纪要。",
                prompt: [
                    "Turn this audio into concise meeting notes.",
                    "Preserve explicitly spoken decisions, todos, times, names, project names, and technical terms.",
                    "Use a short line-by-line list when there are multiple points.",
                    "Do not add facts, conclusions, owners, or deadlines that the user did not say."
                ].joined(separator: "\n")
            )
        }
    }

    private static func addComment(_ comment: [String], indent: Int, to lines: inout [String]) {
        let prefix = String(repeating: " ", count: indent) + "// "
        comment.forEach { lines.append(prefix + $0) }
    }

    private static func jsonString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let raw = String(data: data, encoding: .utf8),
              raw.count >= 2 else {
            return "\"\""
        }
        return String(raw.dropFirst().dropLast())
    }

    private static func jsonStringArray(_ values: [String]) -> String {
        let encoded = values.map(jsonString).joined(separator: ", ")
        return "[\(encoded)]"
    }
}

private struct ConfigDocumentText {
    let language: UILanguage

    var fileIntro: [String] {
        switch language {
        case .chinese:
            return [
                "OmniVoice 会读取这个文件：~/.config/omnivoice/config.jsonc。",
                "如果填写了 API Key，请保持本文件权限为 0600。"
            ]
        case .english:
            return [
                "OmniVoice reads this file at ~/.config/omnivoice/config.jsonc.",
                "Keep this file at permission 0600 when an API key is filled in."
            ]
        }
    }

    var activeSource: [String] {
        language == .chinese
            ? ["API 来源 ID。使用 \"auto\" 时，OmniVoice 会选择测速最快且支持语音模型的来源。"]
            : ["API source ID. Use \"auto\" to let OmniVoice choose the fastest source that supports speech models."]
    }

    var defaultModel: [String] {
        language == .chinese
            ? ["默认语音转写模型。只支持 mimo-v2-omni 或 mimo-v2.5。"]
            : ["Default speech transcription model. Only mimo-v2-omni and mimo-v2.5 are supported."]
    }

    var sources: [String] {
        language == .chinese
            ? ["API 来源列表。每个 key 是来源 ID，只能使用字母、数字、点、下划线和短横线。"]
            : ["API sources. Each key is a source ID using letters, numbers, dots, underscores, or dashes."]
    }

    func source(_ id: String) -> [String] {
        language == .chinese ? ["来源 \(id)。"] : ["Source \(id)."]
    }

    var baseURL: [String] {
        language == .chinese
            ? ["Base URL 可以带或不带 /v1，OmniVoice 会自动归一化。"]
            : ["Base URL may include /v1; OmniVoice normalizes it automatically."]
    }

    var apiKey: [String] {
        language == .chinese
            ? ["填入这个来源的 API Key。菜单和日志只会显示脱敏状态。"]
            : ["API key for this source. Menus and logs only show redacted status."]
    }

    var latency: [String] {
        language == .chinese
            ? ["测速设置。只访问 /v1/models，不发送语音。"]
            : ["Latency settings. Only /v1/models is called; no voice audio is sent."]
    }

    var latencyEnabled: [String] {
        language == .chinese ? ["是否启用后台测速。"] : ["Whether background latency checks are enabled."]
    }

    var latencyInterval: [String] {
        language == .chinese
            ? ["测速间隔秒数。支持 30、60、120、300、900、1800、3600；null 表示只在启动时测速。"]
            : ["Latency interval in seconds. Supported: 30, 60, 120, 300, 900, 1800, 3600; null means startup only."]
    }

    var preferences: [String] {
        language == .chinese
            ? ["菜单中可设置的用户偏好。OmniVoice 会用这些值同步菜单状态。"]
            : ["User preferences exposed in the menu. OmniVoice syncs menu state from these values."]
    }

    var uiLanguage: [String] {
        language == .chinese ? ["界面语言，同时决定本文件注释语言。"] : ["UI language; also controls the language of comments in this file."]
    }

    var transcriptionStyle: [String] {
        language == .chinese
            ? ["默认转写风格。可使用 concise、verbatim、codeFaithful、rewrite，或 custom:<风格 ID>。"]
            : ["Default transcription style. Use concise, verbatim, codeFaithful, rewrite, or custom:<style ID>."]
    }

    var keywordHintsEnabled: [String] {
        language == .chinese
            ? ["是否启用关键词提示。关闭后不会把任何关键词注入转写 prompt。"]
            : ["Whether keyword hints are enabled. When off, no keywords are injected into the transcription prompt."]
    }

    var enabledKeywordGroups: [String] {
        language == .chinese
            ? [
                "当前启用的关键词组 ID。可以在菜单里多选，也可以直接编辑这里。"
            ]
            : [
                "Enabled keyword group IDs. You can multi-select them in the menu or edit this list directly."
            ]
    }

    var triggerKey: [String] {
        language == .chinese
            ? ["录音触发键。默认 fn-globe；也可使用菜单中展示的 F1-F12、修饰键或 Caps Lock ID。"]
            : ["Recording trigger key. Default is fn-globe; menu-listed F1-F12, modifier, and Caps Lock IDs are also supported."]
    }

    var minRecording: [String] {
        language == .chinese ? ["最短录音时间，单位毫秒。"] : ["Minimum recording duration in milliseconds."]
    }

    var maxRecording: [String] {
        language == .chinese ? ["最长录音时间，单位秒。"] : ["Maximum recording duration in seconds."]
    }

    var autoInsert: [String] {
        language == .chinese ? ["是否在目标输入框安全可写时自动插入最终文本。"] : ["Whether final text is auto-inserted when the focused field is safe."]
    }

    var launchAtLogin: [String] {
        language == .chinese ? ["是否开机自启。菜单切换时也会同步系统登录项。"] : ["Whether to launch at login. Menu changes also sync the system Login Item."]
    }

    var hud: [String] {
        language == .chinese ? ["HUD 和短提示显示设置。"] : ["HUD and short-message display settings."]
    }

    var hudVisualStyle: [String] {
        language == .chinese
            ? ["HUD 视觉样式：automatic 会跟随系统亮暗外观；也可固定为 darkCapsule、lightCapsule；macOS 26+ 可使用 liquidGlass。"]
            : ["HUD visual style: automatic follows the system light/dark appearance; fixed darkCapsule and lightCapsule are also available; liquidGlass is available on macOS 26+."]
    }

    var hudMessageDuration: [String] {
        language == .chinese ? ["短状态或 warning 提示停留秒数。"] : ["How many seconds short status or warning messages stay visible."]
    }

    var hudRevealDelay: [String] {
        language == .chinese
            ? ["按下触发键后多久显示聆听 HUD，单位毫秒。录音仍会立即开始。"]
            : ["Delay before the listening HUD appears after pressing the trigger, in milliseconds. Recording starts immediately."]
    }

    var customStyles: [String] {
        language == .chinese
            ? ["自定义转写风格，会显示在“风格”菜单和结果面板风格切换中。"]
            : ["Custom transcription styles shown in the Style menu and result-panel style switcher."]
    }

    func customStyle(_ id: String) -> [String] {
        language == .chinese ? ["自定义风格 \(id)。"] : ["Custom style \(id)."]
    }

    var customDisplayName: [String] {
        language == .chinese ? ["英文显示名。"] : ["English display name."]
    }

    var customDisplayNameZH: [String] {
        language == .chinese ? ["中文显示名。"] : ["Chinese display name."]
    }

    var customDescription: [String] {
        language == .chinese ? ["英文说明，会用作菜单 tooltip。"] : ["English description, used as a menu tooltip."]
    }

    var customDescriptionZH: [String] {
        language == .chinese ? ["中文说明，会用作菜单 tooltip。"] : ["Chinese description, used as a menu tooltip."]
    }

    var customPromptLines: [String] {
        language == .chinese
            ? ["转写 prompt。写清楚语气、格式和禁止事项，不要要求新增用户没说的事实。"]
            : ["Transcription prompt. State tone, format, and constraints; do not ask for facts the user did not say."]
    }

    var keywordGroups: [String] {
        language == .chinese
            ? ["关键词组会作为识别提示注入 prompt，用于专有名词、产品名、命令、路径和领域术语消歧。"]
            : ["Keyword groups are injected as recognition hints for proper nouns, product names, commands, paths, and domain terms."]
    }

    func keywordGroup(_ id: String) -> [String] {
        language == .chinese ? ["关键词组 \(id)。"] : ["Keyword group \(id)."]
    }

    var keywordDisplayName: [String] {
        language == .chinese
            ? ["显示名。只写一种语言即可；另一种界面语言会自动回退到已有名称。"]
            : ["Display name. One language is enough; the other UI language falls back to the name that exists."]
    }

    var keywordDescription: [String] {
        language == .chinese
            ? ["说明，会用作菜单 tooltip；只写一种语言即可。"]
            : ["Description used as the menu tooltip; one language is enough."]
    }

    var keywords: [String] {
        language == .chinese
            ? ["关键词列表。每组最多 200 个；总计最多注入 500 个；不要写换行或控制字符。"]
            : ["Keyword list. Up to 200 per group and 500 injected in total; do not include newlines or control characters."]
    }
}

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
    public let warnings: [String]

    public var displayLines: [String] {
        var lines = [
            "Source: \(activeSourceID)",
            "Base URL: \(baseURLHost)",
            "API Key: \(apiKeyPreview)",
            "Default Model: \(defaultModel.rawValue)",
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
           let object = readJSONObject(url: configFileURL),
           validationIssues(for: object).isEmpty,
           let file = readFileConfig(url: configFileURL, source: .configFile) {
            return file
        }

        if fileManager.fileExists(atPath: configFileURL.path) {
            _ = backupExistingConfig()
        }
        guard writeDefaultConfig(uiLanguage: uiLanguage) else {
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
        let issues = validationIssues(for: object)
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
        let selected = APISourceResolver.resolvedSource(activeSourceID: activeID, sources: current.sources, latencyResults: [:])
        let output = MimoConfig(
            baseURL: selected?.baseURL ?? current.baseURL,
            apiKey: selected?.apiKey ?? current.apiKey,
            defaultModel: current.defaultModel,
            source: .configFile,
            activeSourceID: activeID,
            resolvedSourceID: selected?.id ?? current.resolvedSourceID,
            sources: current.sources,
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
            customStyles: current.customStyles,
            keywordGroups: current.keywordGroups,
            latencySettings: current.latencySettings,
            preferences: preferences
        )
        return writeConfig(output, uiLanguage: preferences.uiLanguage)
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
            guard let object = readJSONObject(url: url) else {
                return MimoConfig(source: source, warnings: warnings + ["Config warning: config.jsonc could not be read"])
            }
            let parsed = parse(object: object, source: source, warnings: warnings)
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

    private func readJSONObject(url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        let stripped = JSONCNormalizer.normalize(raw)
        guard let jsonData = stripped.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        return object
    }

    private func parse(object: [String: Any], source: ConfigSource, warnings: [String]) -> MimoConfig {
        let defaultModel = AllowedSpeechModel.safeSelection(object["default_model"] as? String)
        let latencySettings = parseLatencySettings(object["latency"] as? [String: Any])
        let sources = parseSources(object: object)
        let customStyles = parseCustomStyles(object["custom_styles"] as? [String: Any])
        let keywordParse = parseKeywordGroups(object["keyword_groups"] as? [String: Any])
        let preferences = parsePreferences(object["preferences"] as? [String: Any], selectedModel: defaultModel)
            ?? .defaultPreferences(selectedModel: defaultModel)
        let activeID = (object["active_source"] as? String)?.nilIfBlank
            ?? MimoConfig.autoSourceID
        let selected = APISourceResolver.resolvedSource(
            activeSourceID: activeID,
            sources: sources,
            latencyResults: [:]
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
        if object["sources"] == nil {
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
        guard let selected else {
            return MimoConfig(
                source: .missing,
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
            customStyles: customStyles,
            keywordGroups: keywordParse.groups,
            latencySettings: latencySettings,
            preferences: preferences,
            warnings: outputWarnings
        )
    }

    private func parseSources(object: [String: Any]) -> [MimoConfigSource] {
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

    private func parseCustomStyles(_ rawStyles: [String: Any]?) -> [CustomTranscriptionStyle] {
        guard let rawStyles else { return [] }
        return rawStyles.compactMap { id, value in
            guard CustomTranscriptionStyleValidator.isValidID(id),
                  let object = value as? [String: Any] else { return nil }
            let prompt = customPrompt(from: object)
            guard CustomTranscriptionStyleValidator.isValidPrompt(prompt) else { return nil }
            let displayName = (object["display_name"] as? String)?.nilIfBlank
                ?? (object["display_name_zh"] as? String)?.nilIfBlank
                ?? id
            return CustomTranscriptionStyle(
                id: id,
                displayName: displayName,
                displayNameZH: (object["display_name_zh"] as? String)?.nilIfBlank
                    ?? (object["display_name"] as? String)?.nilIfBlank,
                description: (object["description"] as? String)?.nilIfBlank
                    ?? (object["description_zh"] as? String)?.nilIfBlank,
                descriptionZH: (object["description_zh"] as? String)?.nilIfBlank
                    ?? (object["description"] as? String)?.nilIfBlank,
                prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    private func parseKeywordGroups(_ rawGroups: [String: Any]?) -> (groups: [KeywordGroup], warnings: [String]) {
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
            let displayNameZH = (object["display_name_zh"] as? String)?.nilIfBlank
            let description = (object["description"] as? String)?.nilIfBlank
            let descriptionZH = (object["description_zh"] as? String)?.nilIfBlank
            return KeywordGroup(
                id: id,
                displayName: displayName ?? displayNameZH,
                displayNameZH: displayNameZH ?? displayName,
                description: description ?? descriptionZH,
                descriptionZH: descriptionZH ?? description,
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

    private func customPrompt(from object: [String: Any]) -> String {
        if let prompt = object["prompt"] as? String {
            return prompt
        }
        if let lines = object["prompt_lines"] as? [String] {
            return lines.joined(separator: "\n")
        }
        return ""
    }

    private func parseLatencySettings(_ object: [String: Any]?) -> ConfigLatencySettings {
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

    private func parsePreferences(_ object: [String: Any]?, selectedModel: AllowedSpeechModel) -> ConfigPreferences? {
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
        let selection = TranscriptionStyleSelection(rawValue: styleRaw)
        guard selection.builtInStyle != nil ||
              (styleRaw.hasPrefix(TranscriptionStyleSelection.customPrefix) &&
               CustomTranscriptionStyleValidator.isValidID(String(styleRaw.dropFirst(TranscriptionStyleSelection.customPrefix.count)))) else {
            return nil
        }
        let keywordHintsEnabled = object["keyword_hints_enabled"] as? Bool ?? true
        let enabledKeywordGroupIDs = (object["enabled_keyword_groups"] as? [String] ?? [])
            .filter(KeywordGroupValidator.isValidID)
        return ConfigPreferences(
            selectedModel: selectedModel,
            uiLanguage: uiLanguage,
            transcriptionStyleSelection: selection,
            keywordHintsEnabled: keywordHintsEnabled,
            enabledKeywordGroupIDs: enabledKeywordGroupIDs,
            triggerKey: triggerKey,
            minRecordingDuration: minDuration,
            maxRecordingDuration: maxDuration,
            autoInsert: autoInsert,
            launchAtLogin: launchAtLogin,
            hudVisualStyle: hudVisualStyle,
            hudMessageDuration: messageDuration,
            hudRevealDelay: revealDelay
        )
    }

    private func validationIssues(for object: [String: Any]) -> [String] {
        var issues: [String] = []
        guard let defaultModelRaw = object["default_model"] as? String,
              AllowedSpeechModel(rawValue: defaultModelRaw) != nil else {
            issues.append("default_model")
            return issues
        }
        let defaultModel = AllowedSpeechModel.safeSelection(defaultModelRaw)
        let sources = parseSources(object: object)
        if sources.isEmpty {
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

    private func preferredWriteLanguage(fallback: UILanguage) -> UILanguage {
        guard let object = readJSONObject(url: configFileURL),
              let defaultModelRaw = object["default_model"] as? String,
              let defaultModel = AllowedSpeechModel(rawValue: defaultModelRaw),
              let preferences = parsePreferences(object["preferences"] as? [String: Any], selectedModel: defaultModel) else {
            return fallback
        }
        return preferences.uiLanguage
    }
}

public enum JSONCNormalizer {
    public static func normalize(_ input: String) -> String {
        removeTrailingCommas(from: removeComments(from: input))
    }

    public static func removeComments(from input: String) -> String {
        var output = ""
        var index = input.startIndex
        var inString = false
        var escaping = false
        while index < input.endIndex {
            let char = input[index]
            let next = input.index(after: index)
            if inString {
                output.append(char)
                if escaping {
                    escaping = false
                } else if char == "\\" {
                    escaping = true
                } else if char == "\"" {
                    inString = false
                }
                index = next
                continue
            }
            if char == "\"" {
                inString = true
                output.append(char)
                index = next
                continue
            }
            if char == "/", next < input.endIndex {
                let nextChar = input[next]
                if nextChar == "/" {
                    index = input.index(after: next)
                    while index < input.endIndex, input[index] != "\n" {
                        index = input.index(after: index)
                    }
                    if index < input.endIndex {
                        output.append("\n")
                        index = input.index(after: index)
                    }
                    continue
                }
                if nextChar == "*" {
                    index = input.index(after: next)
                    while index < input.endIndex {
                        let blockNext = input.index(after: index)
                        if input[index] == "*", blockNext < input.endIndex, input[blockNext] == "/" {
                            index = input.index(after: blockNext)
                            break
                        }
                        index = blockNext
                    }
                    continue
                }
            }
            output.append(char)
            index = next
        }
        return output
    }

    public static func removeTrailingCommas(from input: String) -> String {
        var output = ""
        var index = input.startIndex
        var inString = false
        var escaping = false
        while index < input.endIndex {
            let char = input[index]
            if inString {
                output.append(char)
                if escaping {
                    escaping = false
                } else if char == "\\" {
                    escaping = true
                } else if char == "\"" {
                    inString = false
                }
                index = input.index(after: index)
                continue
            }
            if char == "\"" {
                inString = true
                output.append(char)
                index = input.index(after: index)
                continue
            }
            if char == "," {
                var lookahead = input.index(after: index)
                while lookahead < input.endIndex, input[lookahead].isWhitespace {
                    lookahead = input.index(after: lookahead)
                }
                if lookahead < input.endIndex, (input[lookahead] == "}" || input[lookahead] == "]") {
                    index = input.index(after: index)
                    continue
                }
            }
            output.append(char)
            index = input.index(after: index)
        }
        return output
    }
}

private extension URL {
    var normalizedMimoBaseURL: URL? {
        MimoConfig.normalizedBaseURL(from: absoluteString)
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
