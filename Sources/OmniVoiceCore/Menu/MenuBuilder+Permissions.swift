import AppKit
import Foundation

@MainActor
extension MenuBuilder {
    func permissionsMenu(snapshot: PermissionSnapshot) -> NSMenu {
        let menu = NSMenu(title: coordinator.strings.permissions)
        menu.addItem(PermissionMenuPresenter(
            strings: coordinator.strings,
            uiLanguage: coordinator.settings.uiLanguage
        ).summaryItem(snapshot))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(
            title: coordinator.strings.requestAllPermissions,
            action: #selector(AppCoordinator.requestAllPermissions),
            tooltip: coordinator.strings.tooltip(.requestAllPermissions)
        ))
        menu.addItem(item(
            title: coordinator.strings.requestMicrophone,
            action: #selector(AppCoordinator.requestMicrophonePermission),
            tooltip: coordinator.strings.tooltip(.requestMicrophone)
        ))
        menu.addItem(item(
            title: coordinator.strings.requestAccessibility,
            action: #selector(AppCoordinator.requestAccessibilityPermission),
            tooltip: coordinator.strings.tooltip(.requestAccessibility)
        ))
        menu.addItem(item(
            title: coordinator.strings.requestInputMonitoring,
            action: #selector(AppCoordinator.requestInputMonitoringPermission),
            tooltip: coordinator.strings.tooltip(.requestInputMonitoring)
        ))
        menu.addItem(item(
            title: coordinator.strings.requestSpeechRecognition,
            action: #selector(AppCoordinator.requestSpeechRecognitionPermission),
            tooltip: coordinator.strings.tooltip(.requestSpeechRecognition)
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(title: coordinator.strings.openMicrophoneSettings, action: #selector(AppCoordinator.openMicrophoneSettings)))
        menu.addItem(item(title: coordinator.strings.openAccessibilitySettings, action: #selector(AppCoordinator.openAccessibilitySettings)))
        menu.addItem(item(title: coordinator.strings.openInputMonitoringSettings, action: #selector(AppCoordinator.openInputMonitoringSettings)))
        menu.addItem(item(title: coordinator.strings.openSpeechRecognitionSettings, action: #selector(AppCoordinator.openSpeechRecognitionSettings)))
        return menu
    }
}
