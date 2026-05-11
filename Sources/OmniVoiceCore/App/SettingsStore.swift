import Foundation

/// UserDefaults-backed runtime flags.
///
/// User-facing app configuration is owned by `AppConfigStore`; this store only
/// keeps launch/runtime state that should survive process restarts.
final class SettingsStore: @unchecked Sendable {
    static let shared = SettingsStore()

    enum Key {
        static let listeningEnabled = "OmniVoice.listeningEnabled"
        static let didRunStartupPermissionGuide = "OmniVoice.didRunStartupPermissionGuide"
        static let startupPermissionGuideIdentity = "OmniVoice.startupPermissionGuideIdentity"
        static let runtimeActive = "OmniVoice.runtimeActive"
        static let stopReason = "OmniVoice.stopReason"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.listeningEnabled: true
        ])
    }

    var listeningEnabled: Bool {
        get { defaults.bool(forKey: Key.listeningEnabled) }
        set { defaults.set(newValue, forKey: Key.listeningEnabled) }
    }

    var didRunStartupPermissionGuide: Bool {
        get { defaults.bool(forKey: Key.didRunStartupPermissionGuide) }
        set { defaults.set(newValue, forKey: Key.didRunStartupPermissionGuide) }
    }

    var startupPermissionGuideIdentity: String? {
        get { defaults.string(forKey: Key.startupPermissionGuideIdentity) }
        set { defaults.set(newValue, forKey: Key.startupPermissionGuideIdentity) }
    }

    var runtimeActive: Bool {
        get { defaults.bool(forKey: Key.runtimeActive) }
        set { defaults.set(newValue, forKey: Key.runtimeActive) }
    }

    var stopReason: StopReason? {
        get {
            guard let raw = defaults.string(forKey: Key.stopReason) else {
                return nil
            }
            return StopReason(rawValue: raw)
        }
        set {
            if let newValue {
                defaults.set(newValue.rawValue, forKey: Key.stopReason)
            } else {
                defaults.removeObject(forKey: Key.stopReason)
            }
        }
    }

}

enum AppSafetyPlanner {
    static func shouldStartInSafeMode(previousRuntimeActive: Bool) -> Bool {
        previousRuntimeActive
    }
}
