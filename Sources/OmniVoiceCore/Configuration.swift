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
    public let latencySettings: ConfigLatencySettings
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
        latencySettings: ConfigLatencySettings = .defaultSettings,
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
        self.latencySettings = latencySettings
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
            latencySettings: latencySettings,
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
            latencySettings: latencySettings,
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

public enum ConfigTemplateBuilder {
    public static func template(uiLanguage: UILanguage) -> String {
        switch uiLanguage {
        case .chinese:
            return """
            {
              // OmniVoice 会读取这个文件：~/.config/omnivoice/config.jsonc
              // active_source 可以写成 "auto"，让 OmniVoice 自动选择最快可用来源。
              "active_source": "auto",
              "default_model": "mimo-v2-omni",
              "sources": {
                // 你可以把 config1 改成更容易识别的名字，例如 sgp、cn 或 work。
                "config1": {
                  // Base URL 可以带或不带 /v1，OmniVoice 会自动归一化。
                  "base_url": "https://token-plan-sgp.xiaomimimo.com",
                  // 填入你的 API Key；保存后请保持本文件权限为 0600。
                  "api_key": ""
                }
              },
              "latency": {
                // 用 /v1/models 做轻量测速，不发送语音。
                "enabled": true,
                "interval_seconds": 1800
              },
              "custom_styles": {
                // 自定义转写风格会出现在“风格”菜单和结果面板的风格切换中。
                // 风格 ID 只能使用字母、数字、点、下划线和短横线，且不能和内置风格重名。
                "meeting_notes": {
                  "display_name": "Meeting Notes",
                  "display_name_zh": "会议纪要",
                  "description": "Turn speech into concise meeting notes.",
                  "description_zh": "把口述整理成简洁会议纪要。",
                  // 普通用户建议优先修改下面几行：写清楚想要的语气、格式和禁止事项。
                  // 不要要求模型新增事实、收件人、署名、承诺或没有说出的内容。
                  "prompt_lines": [
                    "请把这段音频整理成简洁会议纪要。",
                    "保留明确说出的决定、待办、时间、人名、项目名和技术词。",
                    "如果有多个要点，使用简短的换行列表。",
                    "不要新增用户没有说出的事实、结论、负责人或截止日期。"
                  ]
                }
              }
            }
            """
        case .english:
            return """
            {
              // OmniVoice reads this file at ~/.config/omnivoice/config.jsonc.
              // Set active_source to "auto" to let OmniVoice choose the fastest usable source.
              "active_source": "auto",
              "default_model": "mimo-v2-omni",
              "sources": {
                // Rename config1 to a memorable source name, such as sgp, cn, or work.
                "config1": {
                  // Base URL may include /v1; OmniVoice normalizes it automatically.
                  "base_url": "https://token-plan-sgp.xiaomimimo.com",
                  // Fill in your API key and keep this file permission at 0600.
                  "api_key": ""
                }
              },
              "latency": {
                // Uses /v1/models for lightweight latency checks. No voice audio is sent.
                "enabled": true,
                "interval_seconds": 1800
              },
              "custom_styles": {
                // Custom transcription styles appear in the Style menu and in the result panel style switcher.
                // Style IDs may use letters, numbers, dots, underscores, and dashes. Do not reuse a built-in style ID.
                "meeting_notes": {
                  "display_name": "Meeting Notes",
                  "display_name_zh": "会议纪要",
                  "description": "Turn speech into concise meeting notes.",
                  "description_zh": "把口述整理成简洁会议纪要。",
                  // Most users only need to edit these prompt lines: say what tone and format you want,
                  // and name what must not be invented.
                  "prompt_lines": [
                    "Turn this audio into concise meeting notes.",
                    "Preserve explicitly spoken decisions, todos, times, names, project names, and technical terms.",
                    "Use a short line-by-line list when there are multiple points.",
                    "Do not add facts, conclusions, owners, or deadlines that the user did not say."
                  ]
                }
              }
            }
            """
        }
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

    @discardableResult
    public func saveActiveSource(_ activeSourceID: String) -> Bool {
        let activeID = activeSourceID.nilIfBlank ?? MimoConfig.defaultSourceID
        guard activeID == MimoConfig.autoSourceID || ConfigSourceNameValidator.isValid(activeID) else { return false }
        var object = existingJSONObjectForSave()
        object["active_source"] = activeID
        return writeJSONObject(object)
    }

    @discardableResult
    public func createTemplateIfMissing(uiLanguage: UILanguage) -> Bool {
        guard !fileManager.fileExists(atPath: configFileURL.path) else {
            return true
        }
        do {
            let directory = configFileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = Data(ConfigTemplateBuilder.template(uiLanguage: uiLanguage).utf8)
            try data.write(to: configFileURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFileURL.path)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public func saveLatencyInterval(_ interval: ConfigLatencyInterval) -> Bool {
        var object = existingJSONObjectForSave()
        var latency = object["latency"] as? [String: Any] ?? [:]
        latency["enabled"] = interval != .off
        if let seconds = interval.seconds {
            latency["interval_seconds"] = seconds
        } else {
            latency["interval_seconds"] = NSNull()
        }
        latency.removeValue(forKey: "interval_minutes")
        object["latency"] = latency
        return writeJSONObject(object)
    }

    private func existingJSONObjectForSave() -> [String: Any] {
        if let object = readJSONObject(url: configFileURL) {
            return object
        }
        return [
            "active_source": MimoConfig.autoSourceID,
            "default_model": AllowedSpeechModel.defaultModel.rawValue,
            "sources": [:],
            "latency": [
                "enabled": true,
                "interval_seconds": ConfigLatencyInterval.defaultInterval.rawValue
            ]
        ]
    }

    private func writeJSONObject(_ object: [String: Any]) -> Bool {
        do {
            let directory = configFileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
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
                    latencySettings: parsed.latencySettings,
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
        let activeID = (object["active_source"] as? String)?.nilIfBlank
            ?? MimoConfig.autoSourceID
        let selected = APISourceResolver.resolvedSource(
            activeSourceID: activeID,
            sources: sources,
            latencyResults: [:]
        )
        var outputWarnings = warnings
        if object["sources"] == nil {
            outputWarnings.append("Config warning: config.jsonc must use sources")
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
                latencySettings: latencySettings,
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
            latencySettings: latencySettings,
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
            let displayName = (object["display_name"] as? String)?.nilIfBlank ?? id
            return CustomTranscriptionStyle(
                id: id,
                displayName: displayName,
                displayNameZH: object["display_name_zh"] as? String,
                description: object["description"] as? String,
                descriptionZH: object["description_zh"] as? String,
                prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
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
