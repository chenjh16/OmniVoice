import AppKit
import Foundation

@MainActor
final class MenuBuilder {
    private unowned let coordinator: AppCoordinator

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func build() -> NSMenu {
        let snapshot = MenuStateSnapshot(coordinator: coordinator)
        let permissionPresenter = PermissionMenuPresenter(
            strings: coordinator.strings,
            uiLanguage: snapshot.uiLanguage
        )
        let menu = NSMenu(title: AppConstants.productName)
        menu.delegate = coordinator

        menu.addItem(coordinator.item(
            title: snapshot.globalStopActive || !snapshot.listeningEnabled ? coordinator.strings.reenable : coordinator.strings.stop,
            action: #selector(AppCoordinator.toggleGlobalStop),
            tooltip: coordinator.strings.tooltip(.globalStop)
        ))
        menu.addItem(coordinator.disabledItem("\(coordinator.strings.statusPrefix): \(snapshot.statusTitle)"))
        menu.addItem(permissionPresenter.summaryItem(snapshot.permissionSnapshot))
        menu.addItem(coordinator.item(
            title: coordinator.strings.requestAllPermissions,
            action: #selector(AppCoordinator.requestAllPermissions),
            tooltip: coordinator.strings.tooltip(.requestAllPermissions)
        ))
        menu.addItem(NSMenuItem.separator())

        if snapshot.pipelineMode == .systemASROnly {
            menu.addItem(coordinator.disabledItem("\(coordinator.strings.baseURLPrefix): \(coordinator.strings.systemASRNoAPIBaseURL)"))
            menu.addItem(coordinator.disabledItem("\(coordinator.strings.apiKeyPrefix): \(coordinator.strings.apiKeyUnused)"))
        } else {
            menu.addItem(coordinator.disabledItem("\(coordinator.strings.baseURLPrefix): \(snapshot.displayConfig.redactedStatus.baseURLHost)"))
            menu.addItem(coordinator.disabledItem("\(coordinator.strings.apiKeyPrefix): \(coordinator.strings.apiKeyStatus(snapshot.displayConfig))"))
        }
        menu.addItem(coordinator.disabledItem(coordinator.strings.transcriptionSummaryTitle(
            mode: snapshot.pipelineMode,
            model: snapshot.currentPipelineModel,
            engine: snapshot.systemASREngine
        )))
        for warning in snapshot.configWarnings {
            menu.addItem(coordinator.disabledItem(coordinator.strings.configWarning(warning)))
        }
        if let lastConfigHotReloadMessage = snapshot.lastConfigHotReloadMessage {
            menu.addItem(coordinator.disabledItem(lastConfigHotReloadMessage))
        }
        menu.addItem(coordinator.submenuItem(
            coordinator.strings.configurationTitle(snapshot.displayConfig),
            submenu: coordinator.configurationMenu(),
            tooltip: coordinator.strings.tooltip(.configuration)
        ))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(coordinator.submenuItem(
            MenuTitleFormatter.language(snapshot.uiLanguage, uiLanguage: snapshot.uiLanguage),
            submenu: coordinator.languageMenu()
        ))
        menu.addItem(coordinator.submenuItem(
            MenuTitleFormatter.style(snapshot.styleDescriptor, uiLanguage: snapshot.uiLanguage),
            submenu: coordinator.styleMenu()
        ))
        menu.addItem(coordinator.submenuItem(
            coordinator.strings.keywordHintsTitle(
                enabled: snapshot.keywordHintsEnabled,
                selectedCount: snapshot.selectedKeywordGroupCount
            ),
            submenu: coordinator.keywordHintsMenu()
        ))
        menu.addItem(coordinator.submenuItem(
            MenuTitleFormatter.trigger(snapshot.triggerKey, uiLanguage: snapshot.uiLanguage),
            submenu: coordinator.triggerMenu()
        ))
        menu.addItem(coordinator.submenuItem(
            MenuTitleFormatter.recordingDuration(
                min: snapshot.minRecordingDuration,
                max: snapshot.maxRecordingDuration,
                uiLanguage: snapshot.uiLanguage
            ),
            submenu: coordinator.durationMenu()
        ))
        menu.addItem(NSMenuItem.separator())

        let launchAtLogin = coordinator.item(
            title: coordinator.strings.launchAtLogin,
            action: #selector(AppCoordinator.toggleLaunchAtLogin)
        )
        launchAtLogin.state = snapshot.launchAtLoginEnabled ? .on : .off
        launchAtLogin.toolTip = coordinator.strings.tooltip(.launchAtLogin)
        menu.addItem(launchAtLogin)

        let autoInsert = coordinator.item(
            title: coordinator.strings.autoInsert,
            action: #selector(AppCoordinator.toggleAutoInsert)
        )
        autoInsert.state = snapshot.autoInsert ? .on : .off
        autoInsert.toolTip = coordinator.strings.tooltip(.autoInsert)
        menu.addItem(autoInsert)
        menu.addItem(coordinator.submenuItem(coordinator.strings.displayHints, submenu: coordinator.displayHintsMenu()))
        if let lastLaunchAtLoginError = snapshot.lastLaunchAtLoginError {
            menu.addItem(coordinator.disabledItem(lastLaunchAtLoginError))
        }
        menu.addItem(coordinator.submenuItem(
            coordinator.strings.permissionManagement,
            submenu: coordinator.permissionsMenu(snapshot: snapshot.permissionSnapshot)
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(coordinator.item(title: coordinator.strings.restart, action: #selector(AppCoordinator.restartApp)))
        menu.addItem(coordinator.item(title: coordinator.strings.quit, action: #selector(AppCoordinator.quit)))

        return menu
    }
}
