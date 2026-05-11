import ApplicationServices
import Foundation

public enum TextInjectionStrategyPlanner {
    public static func appClassification(
        bundleIdentifier: String? = nil,
        appName: String? = nil
    ) -> TextInjectionAppClassification {
        let bundle = bundleIdentifier?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let name = appName?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        let hiddenAXPasteBundleIDs = Set([
            "com.tencent.xinwechat"
        ])
        if let bundle, hiddenAXPasteBundleIDs.contains(bundle) {
            return .hiddenAXPasteFallback
        }

        let pasteboardOnlyBundleIDs = Set([
            "com.apple.safari",
            "com.google.chrome",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "com.duckduckgo.macos.browser",
            "company.thebrowser.browser",
            "com.quark.desktop",
            "com.apple.mail",
            "com.microsoft.vscode",
            "com.todesktop.230313mzl4w4u92",
            "dev.zed.zed",
            "com.apple.dt.xcode",
            "abnerworks.typora",
            "com.trae.app",
            "cn.trae.app",
            "com.huawei.devecostudio.ds",
            "com.apple.terminal",
            "com.googlecode.iterm2",
            "dev.warp.warp-stable",
            "com.openai.codex",
            "com.openai.chat",
            "com.hnc.discord",
            "notion.id",
            "md.obsidian",
            "com.electron.lark",
            "com.tencent.qq",
            "com.tdesktop.telegram",
            "com.anthropic.claudefordesktop",
            "com.kangfenmao.cherrystudio",
            "com.tencent.yuanbao"
        ])
        if let bundle, pasteboardOnlyBundleIDs.contains(bundle) {
            return .pasteboardOnly
        }

        let hiddenAXNameFragments = [
            "wechat", "微信"
        ]
        if let name, hiddenAXNameFragments.contains(where: { name.contains($0) }) {
            return .hiddenAXPasteFallback
        }

        let pasteboardOnlyNameFragments = [
            "codex", "chrome", "safari", "firefox", "edge", "duckduckgo", "arc", "quark",
            "mail", "邮件", "cursor", "visual studio code", "code", "zed", "xcode", "typora",
            "trae", "deveco", "terminal", "终端", "iterm", "warp", "slack", "discord",
            "notion", "obsidian", "lark", "feishu", "飞书", "qq", "telegram", "chatgpt",
            "claude", "cherry studio", "yuanbao", "元宝"
        ]
        if let name, pasteboardOnlyNameFragments.contains(where: { name.contains($0) }) {
            return .pasteboardOnly
        }

        return .nativeCandidate
    }

    public static func allowsHiddenAXPasteFallback(
        current: FocusSnapshot,
        original: FocusSnapshot?
    ) -> Bool {
        guard appClassification(
            bundleIdentifier: current.bundleIdentifier,
            appName: current.appName
        ) == .hiddenAXPasteFallback else {
            return false
        }
        guard !current.isSecure else { return false }
        guard current.failureReason == .targetAppUnresponsive || current.failureReason == .noFocusedElement else {
            return false
        }
        guard let original else { return true }
        return appIdentityMatches(original, current)
    }

    public static func appIdentityMatches(_ lhs: FocusSnapshot, _ rhs: FocusSnapshot) -> Bool {
        if let leftBundle = lhs.bundleIdentifier?.lowercased(),
           let rightBundle = rhs.bundleIdentifier?.lowercased() {
            return leftBundle == rightBundle
        }
        if let leftPID = lhs.pid, let rightPID = rhs.pid {
            return leftPID == rightPID
        }
        if let leftName = lhs.appName?.lowercased(), let rightName = rhs.appName?.lowercased() {
            return leftName == rightName
        }
        return false
    }

    public static func preferredStrategy(
        for traits: AccessibilityInjectionTraits,
        bundleIdentifier: String? = nil,
        appName: String? = nil
    ) -> TextInsertionStrategy {
        guard !traits.isSecure else { return .pasteboard }
        guard appClassification(bundleIdentifier: bundleIdentifier, appName: appName) == .nativeCandidate else {
            return .pasteboard
        }
        let nativeTextRoles = Set([
            kAXTextFieldRole as String,
            kAXTextAreaRole as String
        ])
        guard let role = traits.role, nativeTextRoles.contains(role) else {
            return .pasteboard
        }
        return traits.selectedTextSettable || traits.valueSettable ? .accessibility : .pasteboard
    }
}

public enum AXWriteVerification {
    public static func expectedValue(beforeValue: String, selectedRange: NSRange, replacement: String) -> String? {
        let utf16Count = (beforeValue as NSString).length
        guard selectedRange.location >= 0,
              selectedRange.length >= 0,
              selectedRange.location + selectedRange.length <= utf16Count else {
            return nil
        }
        return (beforeValue as NSString).replacingCharacters(in: selectedRange, with: replacement)
    }

    public static func verifies(
        beforeValue: String?,
        expectedValue: String?,
        afterValue: String?,
        insertedText: String
    ) -> Bool {
        guard let afterValue else {
            return true
        }
        if let expectedValue {
            return afterValue == expectedValue
        }
        if let beforeValue {
            return afterValue != beforeValue && afterValue.contains(insertedText)
        }
        return afterValue.contains(insertedText)
    }
}
