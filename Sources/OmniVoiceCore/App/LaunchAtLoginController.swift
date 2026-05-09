import Foundation
import ServiceManagement

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable(String)
}

public enum LaunchAtLoginController {
    public static func status() -> LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable("Login item not found")
        @unknown default:
            return .unavailable("Unknown login item state")
        }
    }

    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
