import AppKit
import AVFoundation
import CoreGraphics
import ApplicationServices
import Security

public struct PermissionSnapshot: Equatable, Sendable {
    public let microphoneGranted: Bool
    public let accessibilityGranted: Bool
    public let inputMonitoringGranted: Bool

    public var allRequiredGranted: Bool {
        microphoneGranted && accessibilityGranted && inputMonitoringGranted
    }
}

public enum PermissionChecker {
    public static func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            microphoneGranted: microphoneGranted(),
            accessibilityGranted: AXIsProcessTrusted(),
            inputMonitoringGranted: CGPreflightListenEventAccess()
        )
    }

    public static func microphoneGranted() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    public static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    @discardableResult
    public static func requestAccessibilityPrompt() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    public static func requestInputMonitoringPrompt() -> Bool {
        CGRequestListenEventAccess()
    }

    public static func openMicrophoneSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    public static func openAccessibilitySettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    public static func openInputMonitoringSettings() {
        openSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func openSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

public enum PermissionGuideAction: Equatable, Sendable {
    case requestMicrophone
    case requestAccessibility
    case requestInputMonitoring
    case openInputMonitoringSettings
}

public enum PermissionGuidePlanner {
    public static func actions(
        for snapshot: PermissionSnapshot,
        hasRunStartupGuide: Bool,
        isManualRequest: Bool
    ) -> [PermissionGuideAction] {
        guard isManualRequest || !hasRunStartupGuide else {
            return []
        }

        var actions: [PermissionGuideAction] = []
        if !snapshot.microphoneGranted {
            actions.append(.requestMicrophone)
        }
        if !snapshot.accessibilityGranted {
            actions.append(.requestAccessibility)
        }
        if !snapshot.inputMonitoringGranted {
            actions.append(.requestInputMonitoring)
            actions.append(.openInputMonitoringSettings)
        }
        return actions
    }
}

public enum StopReason: String, Equatable, Sendable {
    case manual
    case permissionBlocked
    case previousRunRecovery
}

public enum PermissionLegacyStopReasonMigrationPlanner {
    public static func inferredStopReason(
        listeningEnabled: Bool,
        storedStopReason: StopReason?,
        didRunStartupPermissionGuide: Bool
    ) -> StopReason? {
        guard !listeningEnabled,
              storedStopReason == nil,
              didRunStartupPermissionGuide else {
            return storedStopReason
        }
        return .permissionBlocked
    }
}

public enum PermissionStartupAutoEnablePlanner {
    public static func shouldAutoEnable(
        listeningEnabled: Bool,
        stopReason: StopReason?,
        current: PermissionSnapshot
    ) -> Bool {
        !listeningEnabled &&
        stopReason == .permissionBlocked &&
        current.allRequiredGranted
    }
}

public enum PermissionReadinessPlanner {
    public static func shouldAutoEnable(
        previous: PermissionSnapshot?,
        current: PermissionSnapshot,
        stopReason: StopReason?
    ) -> Bool {
        guard stopReason == .permissionBlocked,
              current.allRequiredGranted else {
            return false
        }
        return previous?.allRequiredGranted == false
    }
}

public enum PermissionListeningStartupPlanner {
    public static func shouldStartListening(
        listeningEnabled: Bool,
        globalStopActive: Bool,
        permissions: PermissionSnapshot,
        hasOtherRunningInstance: Bool
    ) -> Bool {
        listeningEnabled &&
        !globalStopActive &&
        permissions.allRequiredGranted &&
        !hasOtherRunningInstance
    }
}

public enum PermissionDriftPlanner {
    public static func shouldEnterPermissionBlockedStop(
        previous: PermissionSnapshot?,
        current: PermissionSnapshot,
        listeningEnabled: Bool,
        globalStopActive: Bool
    ) -> Bool {
        listeningEnabled &&
        !globalStopActive &&
        previous?.allRequiredGranted == true &&
        !current.allRequiredGranted
    }
}

public enum SingleInstanceLaunchPlanner {
    public static func shouldAllowListening(otherRunningInstanceCount: Int) -> Bool {
        otherRunningInstanceCount == 0
    }
}

public enum EventTapDisabledRecoveryAction: Equatable, Sendable {
    case restartListening
    case enterPermissionBlockedStop
    case stayStopped
}

public enum EventTapDisabledRecoveryPlanner {
    public static func action(
        listeningEnabled: Bool,
        globalStopActive: Bool,
        permissions: PermissionSnapshot
    ) -> EventTapDisabledRecoveryAction {
        guard listeningEnabled, !globalStopActive else {
            return .stayStopped
        }
        return permissions.allRequiredGranted ? .restartListening : .enterPermissionBlockedStop
    }
}

public struct PermissionGuideRunState: Equatable, Sendable {
    public let didRunStartupGuide: Bool
    public let storedIdentity: String?
    public let currentIdentity: String

    public init(didRunStartupGuide: Bool, storedIdentity: String?, currentIdentity: String) {
        self.didRunStartupGuide = didRunStartupGuide
        self.storedIdentity = storedIdentity
        self.currentIdentity = currentIdentity
    }

    public var hasRunForCurrentIdentity: Bool {
        didRunStartupGuide && storedIdentity == currentIdentity
    }
}

public enum PermissionInstallIdentity {
    public static func current(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> String {
        if let signingIdentity = currentCodeSigningIdentity() {
            return signingIdentity
        }

        let bundleIdentifier = bundle.bundleIdentifier ?? "unknown.bundle"
        guard let executableURL = bundle.executableURL else {
            return "\(bundleIdentifier)|no-executable"
        }

        let attributes = (try? fileManager.attributesOfItem(atPath: executableURL.path)) ?? [:]
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return "\(bundleIdentifier)|\(executableURL.path)|\(Int(modified))|\(size)"
    }

    private static func currentCodeSigningIdentity() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return nil
        }

        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any] else {
            return nil
        }

        let identifier = dict[kSecCodeInfoIdentifier as String] as? String ?? "unknown.identifier"
        if let uniqueData = dict[kSecCodeInfoUnique as String] as? Data {
            return "\(identifier)|cdhash:\(uniqueData.map { String(format: "%02x", $0) }.joined())"
        }
        return identifier
    }
}
