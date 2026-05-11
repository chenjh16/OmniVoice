import Foundation

struct AccessibilityPermissionRequestOutcome: Sendable {
    let snapshot: PermissionSnapshot
    let openedSettingsFallback: Bool
}
