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
        let menu = NSMenu(title: AppConstants.productName)
        menu.delegate = coordinator

        menu.addItem(coordinator.item(
            title: snapshot.globalStopActive || !snapshot.listeningEnabled ? coordinator.strings.reenable : coordinator.strings.stop,
            action: #selector(AppCoordinator.toggleGlobalStop),
            tooltip: coordinator.strings.tooltip(.globalStop)
        ))
        menu.addItem(coordinator.disabledItem("\(coordinator.strings.statusPrefix): \(snapshot.statusTitle)"))
        menu.addItem(coordinator.permissionSummaryItem(snapshot.permissionSnapshot))
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

@MainActor
struct MenuStateSnapshot {
    let permissionSnapshot: PermissionSnapshot
    let displayConfig: MimoConfig
    let globalStopActive: Bool
    let listeningEnabled: Bool
    let statusTitle: String
    let pipelineMode: TranscriptionPipelineMode
    let currentPipelineModel: AllowedSpeechModel
    let systemASREngine: SystemASREngine
    let configWarnings: [String]
    let lastConfigHotReloadMessage: String?
    let uiLanguage: UILanguage
    let styleDescriptor: TranscriptionStyleDescriptor
    let keywordHintsEnabled: Bool
    let selectedKeywordGroupCount: Int
    let triggerKey: TriggerKey
    let minRecordingDuration: MinRecordingDuration
    let maxRecordingDuration: MaxRecordingDuration
    let launchAtLoginEnabled: Bool
    let autoInsert: Bool
    let lastLaunchAtLoginError: String?

    init(coordinator: AppCoordinator) {
        let settings = coordinator.settings
        permissionSnapshot = PermissionChecker.snapshot()
        displayConfig = coordinator.config.resolvingSource(using: coordinator.sourceLatencyResults)
        globalStopActive = coordinator.globalStopActive
        listeningEnabled = settings.listeningEnabled
        statusTitle = coordinator.statusTitle
        pipelineMode = settings.pipelineMode
        currentPipelineModel = coordinator.currentPipelineModel
        systemASREngine = coordinator.effectiveSystemASREngine
        configWarnings = coordinator.config.warnings
        lastConfigHotReloadMessage = coordinator.configHotReload.lastMessage
        uiLanguage = settings.uiLanguage
        styleDescriptor = coordinator.currentStyleDescriptor
        keywordHintsEnabled = settings.keywordHintsEnabled
        selectedKeywordGroupCount = coordinator.selectedKeywordGroupCount
        triggerKey = settings.triggerKey
        minRecordingDuration = settings.minRecordingDuration
        maxRecordingDuration = settings.maxRecordingDuration
        launchAtLoginEnabled = LaunchAtLoginController.status() == .enabled
        autoInsert = settings.autoInsert
        lastLaunchAtLoginError = coordinator.lastLaunchAtLoginError
    }
}
