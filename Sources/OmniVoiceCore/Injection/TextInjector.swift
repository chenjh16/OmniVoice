import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

public enum FocusFailureReason: String, Equatable, Sendable {
    case none
    case accessibilityPermissionMissing
    case noFocusedElement
    case notEditable
    case secureField
    case targetAppUnresponsive
    case pasteEventFailed
    case insertionTimeout
    case insertionCancelled
}

public struct FocusSnapshot: Equatable, Sendable {
    public let pid: pid_t?
    public let appName: String?
    public let bundleIdentifier: String?
    public let role: String?
    public let subrole: String?
    public let isEditable: Bool
    public let isSecure: Bool
    public let failureReason: FocusFailureReason

    public init(
        pid: pid_t?,
        appName: String?,
        bundleIdentifier: String?,
        role: String?,
        subrole: String?,
        isEditable: Bool,
        isSecure: Bool,
        failureReason: FocusFailureReason
    ) {
        self.pid = pid
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.role = role
        self.subrole = subrole
        self.isEditable = isEditable
        self.isSecure = isSecure
        self.failureReason = failureReason
    }

    public var canAutoInsert: Bool {
        failureReason == .none && isEditable && !isSecure
    }

    public var summary: String {
        [
            appName,
            role,
            subrole
        ].compactMap { $0 }.joined(separator: " / ")
    }
}

public enum TextInjectionResult: Equatable, Sendable {
    case inserted
    case fallback(FocusFailureReason)
}

public enum TextInsertionStrategy: Equatable, Sendable {
    case accessibility
    case pasteboard
}

public enum TextInjectionAppClassification: Equatable, Sendable {
    case nativeCandidate
    case pasteboardOnly
    case hiddenAXPasteFallback
}

public struct AccessibilityInjectionTraits: Equatable, Sendable {
    public let role: String?
    public let isSecure: Bool
    public let valueSettable: Bool
    public let selectedTextSettable: Bool

    public init(role: String?, isSecure: Bool, valueSettable: Bool, selectedTextSettable: Bool) {
        self.role = role
        self.isSecure = isSecure
        self.valueSettable = valueSettable
        self.selectedTextSettable = selectedTextSettable
    }
}

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

@MainActor
public final class TextInjector {
    public struct Options: Equatable, Sendable {
        public let timeoutSeconds: TimeInterval
        public let pasteWaitNanoseconds: UInt64

        public init(timeoutSeconds: TimeInterval = 2.5, pasteWaitNanoseconds: UInt64 = 550_000_000) {
            self.timeoutSeconds = timeoutSeconds
            self.pasteWaitNanoseconds = pasteWaitNanoseconds
        }
    }

    public var onDiagnostic: ((RuntimeDiagnostic) -> Void)?

    private let options: Options

    public init(options: Options = Options(), onDiagnostic: ((RuntimeDiagnostic) -> Void)? = nil) {
        self.options = options
        self.onDiagnostic = onDiagnostic
    }

    public func captureFocusSnapshot(targetBundleIdentifier: String? = nil) -> FocusSnapshot {
        let requestedApp = targetBundleIdentifier.flatMap { runningApplication(bundleIdentifier: $0) }
        let frontmostApp = requestedApp ?? NSWorkspace.shared.frontmostApplication
        guard AXIsProcessTrusted() else {
            return FocusSnapshot(
                pid: frontmostApp?.processIdentifier,
                appName: frontmostApp?.localizedName,
                bundleIdentifier: frontmostApp?.bundleIdentifier,
                role: nil,
                subrole: nil,
                isEditable: false,
                isSecure: false,
                failureReason: .accessibilityPermissionMissing
            )
        }

        let focused = focusedElementResult(targetApp: requestedApp)
        let error = focused.error
        guard error == .success else {
            let reason: FocusFailureReason = error == .cannotComplete ? .targetAppUnresponsive : .noFocusedElement
            return FocusSnapshot(
                pid: frontmostApp?.processIdentifier,
                appName: frontmostApp?.localizedName,
                bundleIdentifier: frontmostApp?.bundleIdentifier,
                role: nil,
                subrole: nil,
                isEditable: false,
                isSecure: false,
                failureReason: reason
            )
        }
        guard let element = focused.element else {
            return FocusSnapshot(
                pid: frontmostApp?.processIdentifier,
                appName: frontmostApp?.localizedName,
                bundleIdentifier: frontmostApp?.bundleIdentifier,
                role: nil,
                subrole: nil,
                isEditable: false,
                isSecure: false,
                failureReason: .noFocusedElement
            )
        }
        AccessibilityElementReader.setMessagingTimeout(element)

        var pid: pid_t = 0
        let pidResult = AXUIElementGetPid(element, &pid)
        let app = pidResult == .success ? NSRunningApplication(processIdentifier: pid) : frontmostApp
        let role = AccessibilityElementReader.stringAttribute(element, kAXRoleAttribute as CFString)
        let subrole = AccessibilityElementReader.stringAttribute(element, kAXSubroleAttribute as CFString)
        let metadata = [
            role,
            subrole,
            AccessibilityElementReader.stringAttribute(element, kAXTitleAttribute as CFString),
            AccessibilityElementReader.stringAttribute(element, kAXDescriptionAttribute as CFString),
            AccessibilityElementReader.stringAttribute(element, kAXHelpAttribute as CFString),
            AccessibilityElementReader.stringAttribute(element, kAXPlaceholderValueAttribute as CFString),
            AccessibilityElementReader.stringAttribute(element, kAXIdentifierAttribute as CFString)
        ].compactMap { $0 }

        let secure = isSecure(role: role, subrole: subrole, metadata: metadata)
        let editable = isEditable(element: element, role: role)
        let reason: FocusFailureReason
        if secure {
            reason = .secureField
        } else if editable {
            reason = .none
        } else {
            reason = .notEditable
        }

        return FocusSnapshot(
            pid: pidResult == .success ? pid : nil,
            appName: app?.localizedName,
            bundleIdentifier: app?.bundleIdentifier,
            role: role,
            subrole: subrole,
            isEditable: editable,
            isSecure: secure,
            failureReason: reason
        )
    }

    public func insertFinalText(
        _ text: String,
        originalFocus: FocusSnapshot?,
        targetBundleIdentifier: String? = nil
    ) async -> TextInjectionResult {
        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(options.timeoutSeconds)
        var pasteboardSnapshot: PasteboardSnapshot?
        var shouldRestorePasteboard = false

        emitInjectionDiagnostic(
            stage: "injection_start",
            details: [
                "text_chars": "\(text.count)",
                "timeout_seconds": String(format: "%.2f", options.timeoutSeconds)
            ].merging(originalFocus?.diagnosticDetails(prefix: "original") ?? [:]) { current, _ in current }
        )

        defer {
            if shouldRestorePasteboard, let pasteboardSnapshot {
                let restored = pasteboardSnapshot.restore()
                emitInjectionDiagnostic(
                    stage: "pasteboard_restore",
                    details: [
                        "pasteboard_items": "\(pasteboardSnapshot.itemCount)",
                        "pasteboard_types": "\(pasteboardSnapshot.typeCount)",
                        "pasteboard_restored": String(restored)
                    ]
                )
            }
        }

        guard !isTimedOut(deadline: deadline, stage: "before_focus") else {
            return .fallback(.insertionTimeout)
        }

        let current = captureFocusSnapshot(targetBundleIdentifier: targetBundleIdentifier)
        emitInjectionDiagnostic(stage: "focus_before_insert", details: current.diagnosticDetails(prefix: "current"))
        let hiddenAXPasteFallback = TextInjectionStrategyPlanner.allowsHiddenAXPasteFallback(
            current: current,
            original: originalFocus
        )
        guard current.canAutoInsert || hiddenAXPasteFallback else {
            emitInjectionDiagnostic(
                stage: "injection_fallback",
                details: current.diagnosticDetails(prefix: "current"),
                errorKind: current.failureReason.rawValue
            )
            return .fallback(current.failureReason)
        }
        if hiddenAXPasteFallback {
            emitInjectionDiagnostic(
                stage: "hidden_ax_paste_fallback",
                details: current.diagnosticDetails(prefix: "current")
            )
        }
        if let originalPID = originalFocus?.pid,
           let currentPID = current.pid,
           originalPID != currentPID {
            emitInjectionDiagnostic(
                stage: "injection_fallback",
                details: [
                    "original_pid": "\(originalPID)",
                    "current_pid": "\(currentPID)"
                ],
                errorKind: FocusFailureReason.noFocusedElement.rawValue
            )
            return .fallback(.noFocusedElement)
        }

        guard !isTimedOut(deadline: deadline, stage: "after_focus") else {
            return .fallback(.insertionTimeout)
        }

        if !hiddenAXPasteFallback,
           let element = focusedElement(targetBundleIdentifier: targetBundleIdentifier),
           await attemptAccessibilityInsertion(text: text, element: element, focus: current) {
            emitInjectionDiagnostic(stage: "injection_inserted", details: ["method": "accessibility"])
            return .inserted
        }

        guard !isTimedOut(deadline: deadline, stage: "after_ax_attempt") else {
            return .fallback(.insertionTimeout)
        }

        let inputSourceSnapshot = InputSourceManager.currentInputSource()
        let shouldSwitchInputSource = InputSourceManager.currentInputSourceIsCJK()
        emitInjectionDiagnostic(
            stage: "input_source_snapshot",
            details: [
                "input_source_id": inputSourceSnapshot.identifier ?? "unknown",
                "input_source_is_cjk": String(shouldSwitchInputSource)
            ]
        )
        if shouldSwitchInputSource {
            emitInjectionDiagnostic(
                stage: "input_source_switch_skipped_by_default",
                details: ["input_source_id": inputSourceSnapshot.identifier ?? "unknown"]
            )
        }

        guard !isTimedOut(deadline: deadline, stage: "after_input_source") else {
            return .fallback(.insertionTimeout)
        }

        pasteboardSnapshot = PasteboardSnapshot.capture()
        shouldRestorePasteboard = true
        emitInjectionDiagnostic(
            stage: "pasteboard_capture",
            details: [
                "pasteboard_items": "\(pasteboardSnapshot?.itemCount ?? 0)",
                "pasteboard_types": "\(pasteboardSnapshot?.typeCount ?? 0)"
            ]
        )

        let pasteboardChangeCount = NSPasteboard.general.clearContents()
        let pasteboardWriteSucceeded = NSPasteboard.general.setString(text, forType: .string)
        emitInjectionDiagnostic(
            stage: "pasteboard_write",
            details: [
                "pasteboard_change_count": "\(pasteboardChangeCount)",
                "pasteboard_write_succeeded": String(pasteboardWriteSucceeded),
                "text_chars": "\(text.count)"
            ],
            errorKind: pasteboardWriteSucceeded ? nil : "pasteboard_write_failed"
        )
        guard pasteboardWriteSucceeded else {
            return .fallback(.pasteEventFailed)
        }

        guard !isTimedOut(deadline: deadline, stage: "before_paste_event") else {
            return .fallback(.insertionTimeout)
        }

        emitInjectionDiagnostic(stage: "simulate_paste_start")
        guard simulatePaste() else {
            emitInjectionDiagnostic(
                stage: "simulate_paste_result",
                details: ["paste_event_posted": "false"],
                errorKind: FocusFailureReason.pasteEventFailed.rawValue
            )
            return .fallback(.pasteEventFailed)
        }
        emitInjectionDiagnostic(stage: "simulate_paste_result", details: ["paste_event_posted": "true"])

        do {
            try await Task.sleep(nanoseconds: min(pasteWaitNanoseconds(for: current), remainingNanoseconds(until: deadline)))
        } catch {
            emitInjectionDiagnostic(
                stage: "injection_cancelled",
                details: ["elapsed_seconds": String(format: "%.3f", Date().timeIntervalSince(startedAt))],
                errorKind: FocusFailureReason.insertionCancelled.rawValue
            )
            return .fallback(.insertionCancelled)
        }

        if isTimedOut(deadline: deadline, stage: "after_paste_wait") {
            return .fallback(.insertionTimeout)
        }

        emitInjectionDiagnostic(
            stage: "paste_wait_done",
            details: ["elapsed_seconds": String(format: "%.3f", Date().timeIntervalSince(startedAt))]
        )
        emitInjectionDiagnostic(stage: "injection_inserted", details: ["method": "pasteboard"])
        return .inserted
    }

    private func focusedElement(targetBundleIdentifier: String? = nil) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let targetApp = targetBundleIdentifier.flatMap { runningApplication(bundleIdentifier: $0) }
        return focusedElementResult(targetApp: targetApp).element
    }

    private func focusedElementResult(targetApp: NSRunningApplication?) -> (element: AXUIElement?, error: AXError) {
        if let targetApp {
            let appElement = AXUIElementCreateApplication(targetApp.processIdentifier)
            AccessibilityElementReader.setMessagingTimeout(appElement)
            if let element = AccessibilityElementReader.copyElement(appElement, attribute: kAXFocusedUIElementAttribute as CFString) {
                let role = AccessibilityElementReader.stringAttribute(element, kAXRoleAttribute as CFString)
                if isEditable(element: element, role: role) {
                    return (element, .success)
                }
                if let editable = firstEditableDescendant(in: element) {
                    return (editable, .success)
                }
                return (element, .success)
            }
            if let element = firstEditableDescendant(in: appElement) {
                return (element, .success)
            }
        }

        let systemWide = AXUIElementCreateSystemWide()
        AccessibilityElementReader.setMessagingTimeout(systemWide)
        var focusedValue: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard error == .success else {
            return (nil, error)
        }
        guard let element = AccessibilityElementReader.element(from: focusedValue) else { return (nil, .failure) }
        AccessibilityElementReader.setMessagingTimeout(element)
        return (element, .success)
    }

    private func attemptAccessibilityInsertion(text: String, element: AXUIElement, focus: FocusSnapshot) async -> Bool {
        let traits = accessibilityTraits(element: element, focus: focus)
        let strategy = TextInjectionStrategyPlanner.preferredStrategy(
            for: traits,
            bundleIdentifier: focus.bundleIdentifier,
            appName: focus.appName
        )
        emitInjectionDiagnostic(
            stage: "ax_insert_decision",
            details: [
                "ax_strategy": strategy == .accessibility ? "accessibility" : "pasteboard",
                "ax_app_classification": "\(TextInjectionStrategyPlanner.appClassification(bundleIdentifier: focus.bundleIdentifier, appName: focus.appName))",
                "ax_role": traits.role ?? "unknown",
                "ax_value_settable": String(traits.valueSettable),
                "ax_selected_text_settable": String(traits.selectedTextSettable)
            ]
        )
        guard strategy == .accessibility else { return false }

        emitInjectionDiagnostic(stage: "ax_insert_attempt")
        if traits.selectedTextSettable {
            let beforeValue = AccessibilityElementReader.stringAttribute(element, kAXValueAttribute as CFString)
            let selectedRange = AccessibilityElementReader.selectedTextRange(element: element)
            let expectedValue = beforeValue.flatMap { before in
                selectedRange.flatMap { AXWriteVerification.expectedValue(beforeValue: before, selectedRange: $0, replacement: text) }
            }
            let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
            emitInjectionDiagnostic(
                stage: "ax_insert_result",
                details: [
                    "ax_method": "selected_text",
                    "ax_result": "\(result.rawValue)",
                    "ax_before_len": beforeValue.map { "\(($0 as NSString).length)" } ?? "unreadable",
                    "ax_expected_len": expectedValue.map { "\(($0 as NSString).length)" } ?? "unavailable"
                ],
                errorKind: result == .success ? nil : "ax_selected_text_failed"
            )
            if result == .success,
               await verifyAXWrite(
                   element: element,
                   method: "selected_text",
                   beforeValue: beforeValue,
                   expectedValue: expectedValue,
                   insertedText: text
               ) {
                return true
            }
        }

        guard traits.valueSettable,
              let currentValue = AccessibilityElementReader.stringAttribute(element, kAXValueAttribute as CFString),
              let selectedRange = AccessibilityElementReader.selectedTextRange(element: element) else {
            emitInjectionDiagnostic(stage: "ax_insert_result", errorKind: "ax_value_range_unavailable")
            return false
        }

        let utf16Count = (currentValue as NSString).length
        guard selectedRange.location >= 0,
              selectedRange.length >= 0,
              selectedRange.location + selectedRange.length <= utf16Count else {
            emitInjectionDiagnostic(stage: "ax_insert_result", errorKind: "ax_selected_range_invalid")
            return false
        }

        let nextValue = (currentValue as NSString).replacingCharacters(in: selectedRange, with: text)
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, nextValue as CFString)
        emitInjectionDiagnostic(
            stage: "ax_insert_result",
            details: [
                "ax_method": "value_replace_range",
                "ax_result": "\(result.rawValue)"
            ],
            errorKind: result == .success ? nil : "ax_value_set_failed"
        )
        if result == .success {
            let verified = await verifyAXWrite(
                element: element,
                method: "value_replace_range",
                beforeValue: currentValue,
                expectedValue: nextValue,
                insertedText: text
            )
            if verified {
                AccessibilityElementReader.setSelectedTextRange(
                    element: element,
                    location: selectedRange.location + (text as NSString).length
                )
                return true
            }
        }
        return false
    }

    private func verifyAXWrite(
        element: AXUIElement,
        method: String,
        beforeValue: String?,
        expectedValue: String?,
        insertedText: String
    ) async -> Bool {
        try? await Task.sleep(nanoseconds: 80_000_000)
        let afterValue = AccessibilityElementReader.stringAttribute(element, kAXValueAttribute as CFString)
        let verified = AXWriteVerification.verifies(
            beforeValue: beforeValue,
            expectedValue: expectedValue,
            afterValue: afterValue,
            insertedText: insertedText
        )
        emitInjectionDiagnostic(
            stage: "ax_insert_verify",
            details: [
                "ax_method": method,
                "ax_verified": String(verified),
                "ax_before_len": beforeValue.map { "\(($0 as NSString).length)" } ?? "unreadable",
                "ax_after_len": afterValue.map { "\(($0 as NSString).length)" } ?? "unreadable",
                "ax_expected_len": expectedValue.map { "\(($0 as NSString).length)" } ?? "unavailable"
            ],
            errorKind: verified ? nil : "ax_value_unchanged"
        )
        return verified
    }

    private func accessibilityTraits(element: AXUIElement, focus: FocusSnapshot) -> AccessibilityInjectionTraits {
        return AccessibilityInjectionTraits(
            role: focus.role,
            isSecure: focus.isSecure,
            valueSettable: AccessibilityElementReader.isAttributeSettable(element, kAXValueAttribute as CFString),
            selectedTextSettable: AccessibilityElementReader.isAttributeSettable(element, kAXSelectedTextAttribute as CFString)
        )
    }

    private func runningApplication(bundleIdentifier: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    }

    private func firstEditableDescendant(in root: AXUIElement) -> AXUIElement? {
        var queue: [AXUIElement] = [root]
        var visited = 0
        while !queue.isEmpty, visited < 300 {
            let element = queue.removeFirst()
            visited += 1
            let role = AccessibilityElementReader.stringAttribute(element, kAXRoleAttribute as CFString)
            if isEditable(element: element, role: role) {
                return element
            }

            let preferredAttributes: [CFString] = [
                kAXFocusedWindowAttribute as CFString,
                kAXWindowsAttribute as CFString,
                kAXChildrenAttribute as CFString,
                "AXContents" as CFString
            ]
            for attribute in preferredAttributes {
                if let single = AccessibilityElementReader.copyElement(element, attribute: attribute) {
                    queue.append(single)
                } else {
                    queue.append(contentsOf: AccessibilityElementReader.copyElementArray(element, attribute: attribute))
                }
            }
        }
        return nil
    }

    private func isEditable(element: AXUIElement, role: String?) -> Bool {
        let valueSettable = AccessibilityElementReader.isAttributeSettable(element, kAXValueAttribute as CFString)
        let selectionSettable = AccessibilityElementReader.isAttributeSettable(element, kAXSelectedTextAttribute as CFString)

        let editableRoles = Set([
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String
        ])

        return valueSettable ||
            selectionSettable ||
            (role.map { editableRoles.contains($0) } ?? false)
    }

    private func isSecure(role: String?, subrole: String?, metadata: [String]) -> Bool {
        if subrole == (kAXSecureTextFieldSubrole as String) {
            return true
        }
        let joined = metadata.joined(separator: " ").lowercased()
        let sensitiveTerms = [
            "password", "passcode", "验证码", "校验码", "verification code",
            "one-time", "otp", "2fa", "mfa", "api key", "apikey", "token",
            "secret", "密钥", "令牌", "密码", "security code"
        ]
        return sensitiveTerms.contains { joined.contains($0) }
    }

    private func simulatePaste() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func pasteWaitNanoseconds(for focus: FocusSnapshot) -> UInt64 {
        let classification = TextInjectionStrategyPlanner.appClassification(
            bundleIdentifier: focus.bundleIdentifier,
            appName: focus.appName
        )
        guard classification != .nativeCandidate else {
            return options.pasteWaitNanoseconds
        }
        return max(options.pasteWaitNanoseconds, 900_000_000)
    }

    private func isTimedOut(deadline: Date, stage: String) -> Bool {
        guard Date() >= deadline else { return false }
        emitInjectionDiagnostic(
            stage: "injection_timeout",
            details: ["timeout_stage": stage],
            errorKind: FocusFailureReason.insertionTimeout.rawValue
        )
        return true
    }

    private func remainingNanoseconds(until deadline: Date) -> UInt64 {
        let remaining = max(0.05, deadline.timeIntervalSinceNow)
        return UInt64(remaining * 1_000_000_000)
    }

    private func emitInjectionDiagnostic(
        stage: String,
        details: [String: String] = [:],
        errorKind: String? = nil
    ) {
        let diagnostic = RuntimeDiagnostic(
            stage: stage,
            host: "local",
            errorKind: errorKind,
            details: details.mapValues { value in
                if value.count > 160 {
                    return String(value.prefix(160)) + "..."
                }
                return value
            }
        )
        RuntimeDiagnostic.log(diagnostic)
        onDiagnostic?(diagnostic)
    }
}

private extension FocusSnapshot {
    func diagnosticDetails(prefix: String) -> [String: String] {
        var details: [String: String] = [
            "\(prefix)_editable": String(isEditable),
            "\(prefix)_secure": String(isSecure),
            "\(prefix)_failure": failureReason.rawValue
        ]
        if let pid {
            details["\(prefix)_pid"] = "\(pid)"
        }
        if let appName {
            details["\(prefix)_app"] = appName
        }
        if let bundleIdentifier {
            details["\(prefix)_bundle"] = bundleIdentifier
        }
        if let role {
            details["\(prefix)_role"] = role
        }
        if let subrole {
            details["\(prefix)_subrole"] = subrole
        }
        return details
    }
}
