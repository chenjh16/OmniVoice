import Foundation

public enum LanguagePreference: String, CaseIterable, Codable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-CN"
    case traditionalChinese = "zh-TW"
    case japanese = "ja"
    case korean = "ko"

    public static let defaultLanguage: LanguagePreference = .simplifiedChinese

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁体中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }

    public var instructionName: String {
        switch self {
        case .english: return "English (en)"
        case .simplifiedChinese: return "简体中文（zh-CN）"
        case .traditionalChinese: return "繁体中文（zh-TW）"
        case .japanese: return "日本語（ja）"
        case .korean: return "한국어（ko）"
        }
    }
}

public enum UILanguage: String, CaseIterable, Codable, Sendable {
    case chinese = "zh-Hans"
    case english = "en"

    public static let defaultLanguage: UILanguage = .chinese

    public var displayName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    public static func safeSelection(_ rawValue: String?) -> UILanguage {
        guard let rawValue, let language = UILanguage(rawValue: rawValue) else {
            return .defaultLanguage
        }
        return language
    }

    public static func migratedFromLegacyLanguage(_ rawValue: String?) -> UILanguage {
        rawValue == LanguagePreference.english.rawValue ? .english : .chinese
    }
}

public enum TranscriptionStyle: String, CaseIterable, Codable, Sendable {
    case concise
    case verbatim
    case codeFaithful
    case rewrite

    public static let defaultStyle: TranscriptionStyle = .rewrite
    public static let menuOrder: [TranscriptionStyle] = [.verbatim, .concise, .codeFaithful, .rewrite]

    public var displayName: String {
        switch self {
        case .concise: return "精炼"
        case .verbatim: return "原文"
        case .codeFaithful: return "技术"
        case .rewrite: return "重写"
        }
    }

    public func displayName(in uiLanguage: UILanguage) -> String {
        switch uiLanguage {
        case .chinese:
            return displayName
        case .english:
            switch self {
            case .concise: return "Concise"
            case .verbatim: return "Verbatim"
            case .codeFaithful: return "Technical"
            case .rewrite: return "Rewrite"
            }
        }
    }
}

public struct CustomTranscriptionStyle: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let prompt: String

    public init(
        id: String,
        displayName: String,
        prompt: String
    ) {
        self.id = id
        self.displayName = displayName
        self.prompt = prompt
    }

    public func localizedName(in uiLanguage: UILanguage) -> String {
        displayName
    }

    public func localizedDescription(in uiLanguage: UILanguage) -> String? {
        nil
    }
}

public struct KeywordGroup: Equatable, Sendable {
    public let id: String
    public let displayName: String?
    public let keywords: [String]

    public init(
        id: String,
        displayName: String? = nil,
        keywords: [String]
    ) {
        self.id = id
        self.displayName = displayName?.nilIfBlank
        self.keywords = keywords
    }

    public func localizedName(in uiLanguage: UILanguage) -> String {
        displayName ?? id
    }

    public func localizedDescription(in uiLanguage: UILanguage) -> String? {
        nil
    }
}

public struct KeywordHintsContext: Equatable, Sendable {
    public let isEnabled: Bool
    public let groups: [KeywordGroup]

    public init(isEnabled: Bool = true, groups: [KeywordGroup] = []) {
        self.isEnabled = isEnabled
        self.groups = groups
    }

    public var activeGroups: [KeywordGroup] {
        guard isEnabled else { return [] }
        return groups.filter { !$0.keywords.isEmpty }
    }
}

public enum KeywordGroupValidator {
    public static let maxKeywordsPerGroup = 200
    public static let maxTotalKeywords = 500
    public static let maxASRContextualStrings = 100

    public static func isValidID(_ value: String) -> Bool {
        guard let trimmed = value.nilIfBlank,
              trimmed.count <= 48,
              trimmed != "auto" else {
            return false
        }
        return trimmed.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#,
            options: .regularExpression
        ) != nil
    }

    public static func sanitizedKeyword(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let containsRejectedScalar = trimmed.unicodeScalars.contains { scalar in
            CharacterSet.newlines.contains(scalar) || CharacterSet.controlCharacters.contains(scalar)
        }
        return containsRejectedScalar ? nil : trimmed
    }
}

public struct TranscriptionStyleSelection: RawRepresentable, Codable, Hashable, Sendable {
    public static let customPrefix = "custom:"
    public static let defaultSelection = TranscriptionStyleSelection.builtIn(.rewrite)

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.nilIfBlank ?? TranscriptionStyle.defaultStyle.rawValue
    }

    public static func builtIn(_ style: TranscriptionStyle) -> TranscriptionStyleSelection {
        TranscriptionStyleSelection(rawValue: style.rawValue)
    }

    public static func custom(_ id: String) -> TranscriptionStyleSelection {
        TranscriptionStyleSelection(rawValue: "\(customPrefix)\(id)")
    }

    public var builtInStyle: TranscriptionStyle? {
        TranscriptionStyle(rawValue: rawValue)
    }

    public var customStyleID: String? {
        guard rawValue.hasPrefix(Self.customPrefix) else { return nil }
        return String(rawValue.dropFirst(Self.customPrefix.count)).nilIfBlank
    }
}

public struct TranscriptionStyleDescriptor: Equatable, Sendable {
    public let selection: TranscriptionStyleSelection
    public let displayName: String
    public let displayNameZH: String?
    public let tooltip: String?
    public let tooltipZH: String?
    public let prompt: String?
    public let builtInStyle: TranscriptionStyle?

    public init(
        selection: TranscriptionStyleSelection,
        displayName: String,
        displayNameZH: String? = nil,
        tooltip: String? = nil,
        tooltipZH: String? = nil,
        prompt: String? = nil,
        builtInStyle: TranscriptionStyle? = nil
    ) {
        self.selection = selection
        self.displayName = displayName
        self.displayNameZH = displayNameZH?.nilIfBlank
        self.tooltip = tooltip?.nilIfBlank
        self.tooltipZH = tooltipZH?.nilIfBlank
        self.prompt = prompt?.nilIfBlank
        self.builtInStyle = builtInStyle
    }

    public var isCustom: Bool {
        builtInStyle == nil
    }

    public func localizedName(in uiLanguage: UILanguage) -> String {
        switch uiLanguage {
        case .chinese:
            return displayNameZH ?? displayName
        case .english:
            return displayName
        }
    }

    public func localizedTooltip(in uiLanguage: UILanguage) -> String? {
        switch uiLanguage {
        case .chinese:
            return tooltipZH ?? tooltip
        case .english:
            return tooltip
        }
    }
}

public enum TranscriptionStyleResolver {
    public static func builtInDescriptor(_ style: TranscriptionStyle) -> TranscriptionStyleDescriptor {
        TranscriptionStyleDescriptor(
            selection: .builtIn(style),
            displayName: style.displayName(in: .english),
            displayNameZH: style.displayName(in: .chinese),
            builtInStyle: style
        )
    }

    public static func customDescriptor(_ style: CustomTranscriptionStyle) -> TranscriptionStyleDescriptor {
        TranscriptionStyleDescriptor(
            selection: .custom(style.id),
            displayName: style.displayName,
            prompt: style.prompt,
            builtInStyle: nil
        )
    }

    public static func menuDescriptors(customStyles: [CustomTranscriptionStyle]) -> [TranscriptionStyleDescriptor] {
        TranscriptionStyle.menuOrder.map(builtInDescriptor)
            + customStyles.map(customDescriptor)
    }

    public static func resolve(
        selection: TranscriptionStyleSelection,
        customStyles: [CustomTranscriptionStyle]
    ) -> TranscriptionStyleDescriptor {
        if let customID = selection.customStyleID,
           let custom = customStyles.first(where: { $0.id == customID }) {
            return customDescriptor(custom)
        }
        if let builtIn = selection.builtInStyle {
            return builtInDescriptor(builtIn)
        }
        return builtInDescriptor(.defaultStyle)
    }
}
