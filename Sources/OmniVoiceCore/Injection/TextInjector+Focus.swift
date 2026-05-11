import AppKit
import ApplicationServices
import Foundation

@MainActor
extension TextInjector {
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

    func focusedElement(targetBundleIdentifier: String? = nil) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        let targetApp = targetBundleIdentifier.flatMap { runningApplication(bundleIdentifier: $0) }
        return focusedElementResult(targetApp: targetApp).element
    }

    func focusedElementResult(targetApp: NSRunningApplication?) -> (element: AXUIElement?, error: AXError) {
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

    func runningApplication(bundleIdentifier: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    }

    func firstEditableDescendant(in root: AXUIElement) -> AXUIElement? {
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

    func isEditable(element: AXUIElement, role: String?) -> Bool {
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

    func isSecure(role: String?, subrole: String?, metadata: [String]) -> Bool {
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
}
