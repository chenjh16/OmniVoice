import AppKit
import Foundation

@MainActor
final class MenuBuilder {
    unowned let coordinator: AppCoordinator

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

        menu.addItem(item(
            title: snapshot.globalStopActive || !snapshot.listeningEnabled ? coordinator.strings.reenable : coordinator.strings.stop,
            action: #selector(AppCoordinator.toggleGlobalStop),
            tooltip: coordinator.strings.tooltip(.globalStop)
        ))
        menu.addItem(disabledItem("\(coordinator.strings.statusPrefix): \(snapshot.statusTitle)"))
        menu.addItem(permissionPresenter.summaryItem(snapshot.permissionSnapshot))
        menu.addItem(item(
            title: coordinator.strings.requestAllPermissions,
            action: #selector(AppCoordinator.requestAllPermissions),
            tooltip: coordinator.strings.tooltip(.requestAllPermissions)
        ))
        menu.addItem(NSMenuItem.separator())

        if snapshot.pipelineMode == .systemASROnly {
            menu.addItem(disabledItem("\(coordinator.strings.baseURLPrefix): \(coordinator.strings.systemASRNoAPIBaseURL)"))
            menu.addItem(disabledItem("\(coordinator.strings.apiKeyPrefix): \(coordinator.strings.apiKeyUnused)"))
        } else {
            menu.addItem(disabledItem("\(coordinator.strings.baseURLPrefix): \(snapshot.displayConfig.redactedStatus.baseURLHost)"))
            menu.addItem(disabledItem("\(coordinator.strings.apiKeyPrefix): \(coordinator.strings.apiKeyStatus(snapshot.displayConfig))"))
        }
        menu.addItem(disabledItem(coordinator.strings.transcriptionSummaryTitle(
            mode: snapshot.pipelineMode,
            model: snapshot.currentPipelineModel,
            engine: snapshot.systemASREngine
        )))
        for warning in snapshot.configWarnings {
            menu.addItem(disabledItem(coordinator.strings.configWarning(warning)))
        }
        if let lastConfigHotReloadMessage = snapshot.lastConfigHotReloadMessage {
            menu.addItem(disabledItem(lastConfigHotReloadMessage))
        }
        menu.addItem(submenuItem(
            coordinator.strings.configurationTitle(snapshot.displayConfig),
            submenu: configurationMenu(),
            tooltip: coordinator.strings.tooltip(.configuration)
        ))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(submenuItem(
            MenuTitleFormatter.language(snapshot.uiLanguage, uiLanguage: snapshot.uiLanguage),
            submenu: languageMenu()
        ))
        menu.addItem(submenuItem(
            MenuTitleFormatter.style(snapshot.styleDescriptor, uiLanguage: snapshot.uiLanguage),
            submenu: styleMenu()
        ))
        menu.addItem(submenuItem(
            coordinator.strings.keywordHintsTitle(
                enabled: snapshot.keywordHintsEnabled,
                selectedCount: snapshot.selectedKeywordGroupCount
            ),
            submenu: keywordHintsMenu()
        ))
        menu.addItem(submenuItem(
            MenuTitleFormatter.trigger(snapshot.triggerKey, uiLanguage: snapshot.uiLanguage),
            submenu: triggerMenu()
        ))
        menu.addItem(submenuItem(
            MenuTitleFormatter.recordingDuration(
                min: snapshot.minRecordingDuration,
                max: snapshot.maxRecordingDuration,
                uiLanguage: snapshot.uiLanguage
            ),
            submenu: durationMenu()
        ))
        menu.addItem(NSMenuItem.separator())

        let launchAtLogin = item(
            title: coordinator.strings.launchAtLogin,
            action: #selector(AppCoordinator.toggleLaunchAtLogin)
        )
        launchAtLogin.state = snapshot.launchAtLoginEnabled ? .on : .off
        launchAtLogin.toolTip = coordinator.strings.tooltip(.launchAtLogin)
        menu.addItem(launchAtLogin)

        let autoInsert = item(
            title: coordinator.strings.autoInsert,
            action: #selector(AppCoordinator.toggleAutoInsert)
        )
        autoInsert.state = snapshot.autoInsert ? .on : .off
        autoInsert.toolTip = coordinator.strings.tooltip(.autoInsert)
        menu.addItem(autoInsert)
        menu.addItem(submenuItem(coordinator.strings.displayHints, submenu: displayHintsMenu()))
        if let lastLaunchAtLoginError = snapshot.lastLaunchAtLoginError {
            menu.addItem(disabledItem(lastLaunchAtLoginError))
        }
        menu.addItem(submenuItem(
            coordinator.strings.permissionManagement,
            submenu: permissionsMenu(snapshot: snapshot.permissionSnapshot)
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(title: coordinator.strings.restart, action: #selector(AppCoordinator.restartApp)))
        menu.addItem(item(title: coordinator.strings.quit, action: #selector(AppCoordinator.quit)))

        return menu
    }
}
