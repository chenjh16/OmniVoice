import Foundation

enum ConfigWarning: String, CaseIterable, Sendable {
    case fileMissing = "Config file missing"
    case unreadable = "Config warning: config.jsonc could not be read"
    case secretsFileMode = "Config warning: config.jsonc containing secrets should be chmod 600"
    case invalidBaseURL = "Config warning: invalid Base URL, using default host"
    case activeSourceMissing = "Config warning: active source missing, using first source"
    case mustUseSources = "Config warning: config.jsonc must use sources"
    case needsAtLeastOneSource = "Config warning: config.jsonc needs at least one source"
    case missingPreferences = "Config warning: config.jsonc must include preferences"
    case invalidKeywordGroupsIgnored = "Config warning: invalid keyword groups ignored"
    case invalidKeywordsIgnored = "Config warning: invalid keywords ignored"
    case keywordGroupLimitExceeded = "Config warning: keyword group limit exceeded"
    case keywordHintsTotalLimitExceeded = "Config warning: keyword hints exceed total limit"

    static func raw(_ warning: ConfigWarning) -> String {
        warning.rawValue
    }

    static func localized(_ rawWarning: String, language: UILanguage) -> String {
        guard let warning = ConfigWarning(rawValue: rawWarning) else {
            return rawWarning
        }
        return warning.localized(language: language)
    }

    func localized(language: UILanguage) -> String {
        switch self {
        case .secretsFileMode:
            return language == .chinese
                ? "提醒：config.jsonc 包含 API Key，请保持文件权限为 0600"
                : "Reminder: config.jsonc contains an API key; keep file permissions at 0600"
        case .unreadable:
            return language == .chinese
                ? "提醒：config.jsonc 无法读取，请检查文件格式"
                : "Reminder: config.jsonc could not be read; check the file format"
        case .invalidBaseURL:
            return language == .chinese
                ? "提醒：Base URL 无效，已临时使用默认地址"
                : "Reminder: Base URL is invalid; using the default address for now"
        case .fileMissing:
            return language == .chinese
                ? "提醒：config.jsonc 文件不存在"
                : "Reminder: config.jsonc is missing"
        case .activeSourceMissing:
            return language == .chinese
                ? "提醒：当前来源不存在，已临时使用第一个来源"
                : "Reminder: selected source is missing; using the first source for now"
        case .mustUseSources:
            return language == .chinese
                ? "提醒：config.jsonc 需要使用 sources 多来源格式"
                : "Reminder: config.jsonc must use the multi-source sources format"
        case .needsAtLeastOneSource:
            return language == .chinese
                ? "提醒：config.jsonc 至少需要一个 API 来源"
                : "Reminder: config.jsonc needs at least one API source"
        case .missingPreferences:
            return language == .chinese
                ? "提醒：config.jsonc 缺少 preferences，已使用默认偏好"
                : "Reminder: config.jsonc is missing preferences; defaults are being used"
        case .invalidKeywordGroupsIgnored:
            return language == .chinese
                ? "提醒：部分关键词组无效，已忽略"
                : "Reminder: some keyword groups are invalid and were ignored"
        case .invalidKeywordsIgnored:
            return language == .chinese
                ? "提醒：部分关键词无效，已忽略"
                : "Reminder: some keywords are invalid and were ignored"
        case .keywordGroupLimitExceeded:
            return language == .chinese
                ? "提醒：单个关键词组最多使用 200 个关键词，超出部分已忽略"
                : "Reminder: each keyword group uses at most 200 keywords; extra items were ignored"
        case .keywordHintsTotalLimitExceeded:
            return language == .chinese
                ? "提醒：最多注入 500 个关键词，超出部分不会进入 prompt"
                : "Reminder: at most 500 keywords are injected; extra items are left out of the prompt"
        }
    }
}
