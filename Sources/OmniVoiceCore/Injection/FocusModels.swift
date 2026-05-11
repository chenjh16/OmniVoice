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

extension FocusSnapshot {
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
