import AppKit
import Foundation

public enum MenuLayoutMetrics {
    public static let customViewLeading: CGFloat = 28
}

private struct PendingTranscription: Sendable {
    let result: AudioRecordingResult
    let model: AllowedSpeechModel
    let instruction: String
    let styleSelection: TranscriptionStyleSelection
    let shouldAutoInsert: Bool
    let autoInsertSkipReason: String?
    let originalFocus: FocusSnapshot?
    let fallbackResult: PreviousPanelResult?
}

private struct PreviousPanelResult: Sendable {
    let text: String
    let instruction: String
    let styleSelection: TranscriptionStyleSelection
}

@MainActor
final class AppCoordinator: NSObject, NSMenuDelegate {
    private enum AppState {
        case idle
        case recording
        case transcribing
    }

    private let settings = SettingsStore.shared
    private var config: MimoConfig
    private var client: any TranscriptionClient
    private let recordingSource: any RecordingSource
    private let configLoader: ConfigLoader
    private weak var automationEventSink: (any AutomationEventSink)?
    private let eventTap = EventTapController()
    private let hud = DictationHUDController()
    private let actionPanel = ActionPanelController()
    private let textInjector = TextInjector()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let configWatcher: ConfigFileWatcher

    private var state: AppState = .idle
    private var maxRecordingTimer: Timer?
    private var listeningHUDRevealTimer: Timer?
    private var listeningHUDShownForCurrentRecording = false
    private var transcriptionTask: Task<Void, Never>?
    private var recordingFocus: FocusSnapshot?
    private var recordingStartDate: Date?
    private var tapStatus: String?
    private var isTestingConnection = false
    private var lastTestConnectionResult: TestConnectionResult?
    private var availableModels: [AllowedSpeechModel] = AllowedSpeechModel.allCases
    private var lastDiagnostic: RuntimeDiagnostic?
    private var globalStopActive = false
    private var stopReason: StopReason?
    private var lastPermissionSnapshot: PermissionSnapshot?
    private var permissionReadinessTimer: Timer?
    private var permissionDriftTimer: Timer?
    private var eventTapFailureHUDEnabled = false
    private var pendingTranscription: PendingTranscription?
    private var lastLaunchAtLoginError: String?
    private let triggerCapture = TriggerCaptureController()
    private var triggerCaptureTimeout: Timer?
    private weak var triggerCaptureView: TriggerCaptureMenuView?
    private var triggerCapturePausedListening = false
    private var sourceLatencyResults: [String: SourceLatencyMeasurement] = [:]
    private var latencyTimer: Timer?
    private var automationOptions: RecordingReplayAutomationOptions?
    private var automationContinuation: CheckedContinuation<RecordingReplayAutomationResult, Never>?
    private var automationRecordingResult: AudioRecordingResult?
    private var automationGUIFrameTimer: Timer?
    private var automationGUIFrameIndex = 0
    private var automationPreviousUILanguage: UILanguage?
    private var pendingConfigHotReload = false
    private var lastInvalidConfigFingerprint: String?
    private var lastConfigHotReloadMessage: String?
    private var ignoreConfigFileChangesUntil: Date?

    private var strings: UIStrings {
        UIStrings(language: settings.uiLanguage)
    }

    private var currentStyleDescriptor: TranscriptionStyleDescriptor {
        TranscriptionStyleResolver.resolve(
            selection: settings.transcriptionStyleSelection,
            customStyles: config.customStyles
        )
    }

    private var currentKeywordHintsContext: KeywordHintsContext {
        let enabledIDs = Set(settings.enabledKeywordGroupIDs)
        let groups = config.keywordGroups.filter { enabledIDs.contains($0.id) }
        return KeywordHintsContext(isEnabled: settings.keywordHintsEnabled, groups: groups)
    }

    private var selectedKeywordGroupCount: Int {
        currentKeywordHintsContext.activeGroups.count
    }

    private var warningDuration: TimeInterval {
        settings.hudMessageDuration.seconds
    }

    init(
        recordingSource: any RecordingSource = AudioRecorder(),
        configLoader: ConfigLoader = ConfigLoader(),
        automationEventSink: (any AutomationEventSink)? = nil
    ) {
        let loaded = configLoader.ensureValidConfig(uiLanguage: SettingsStore.shared.uiLanguage)
        config = loaded
        client = MimoAPIClient(config: loaded.resolvingSource(using: [:]))
        self.recordingSource = recordingSource
        self.configLoader = configLoader
        self.configWatcher = ConfigFileWatcher(fileURL: configLoader.configFileURL)
        self.automationEventSink = automationEventSink
        super.init()
        settings.applyConfigPreferences(loaded.preferences)
        client = makeClient(config: loaded)
        self.recordingSource.onRMSLevel = { [weak self] level in
            DispatchQueue.main.async {
                self?.hud.updateRMSLevel(level)
            }
        }
        eventTap.onSignal = { [weak self] signal in
            DispatchQueue.main.async {
                self?.handleEventTapSignal(signal)
            }
        }
        triggerCapture.onSignal = { [weak self] signal in
            DispatchQueue.main.async {
                self?.handleTriggerCaptureSignal(signal)
            }
        }
        textInjector.onDiagnostic = { [weak self] diagnostic in
            self?.recordDiagnostic(diagnostic)
        }
        configWatcher.onChange = { [weak self] in
            DispatchQueue.main.async {
                self?.handleConfigFileChanged()
            }
        }
    }

    private func makeClient(config: MimoConfig) -> any TranscriptionClient {
        MimoAPIClient(config: config.resolvingSource(using: sourceLatencyResults)) { [weak self] diagnostic in
            DispatchQueue.main.async {
                self?.recordDiagnostic(diagnostic)
            }
        }
    }

    private func loadConfig() -> MimoConfig {
        configLoader.ensureValidConfig(uiLanguage: settings.uiLanguage)
    }

    private func applyLoadedConfigPreferences(_ loaded: MimoConfig, syncLaunchAtLogin: Bool) {
        settings.applyConfigPreferences(loaded.preferences)
        normalizeHUDStyleAvailability()
        hud.setVisualStyle(settings.hudVisualStyle)
        actionPanel.setVisualStyle(settings.hudVisualStyle)
        eventTap.update(triggerKey: settings.triggerKey)
        eventTap.updateWatchdogTimeout(seconds: TimeInterval(settings.maxRecordingDuration.rawValue + 5))
        if syncLaunchAtLogin {
            syncLaunchAtLoginPreference(loaded.preferences.launchAtLogin, showWarningHUD: false)
        }
        if settings.listeningEnabled, !globalStopActive {
            tapStatus = eventTap.isRunning ? strings.listeningWithTrigger(settings.triggerKey) : tapStatus
        }
    }

    @discardableResult
    private func persistCurrentPreferences() -> Bool {
        let preferences = settings.configPreferences(
            launchAtLogin: LaunchAtLoginController.status() == .enabled
        )
        markInternalConfigWrite()
        guard configLoader.savePreferences(preferences) else {
            hud.showWarningStatus(strings.operationFailed, duration: warningDuration)
            return false
        }
        config = loadConfig()
        client = makeClient(config: config)
        return true
    }

    private func syncLaunchAtLoginPreference(_ enabled: Bool, showWarningHUD: Bool) {
        let isEnabled = LaunchAtLoginController.status() == .enabled
        guard isEnabled != enabled else {
            lastLaunchAtLoginError = nil
            return
        }
        do {
            try LaunchAtLoginController.setEnabled(enabled)
            lastLaunchAtLoginError = nil
        } catch {
            lastLaunchAtLoginError = sanitizedMessage(for: error)
            if showWarningHUD {
                hud.showWarningStatus(lastLaunchAtLoginError ?? strings.operationFailed, duration: warningDuration)
            }
        }
    }

    private func diagnosticRuntimeDetails(_ details: [String: String] = [:]) -> [String: String] {
        var output = details
        output["pid"] = "\(ProcessInfo.processInfo.processIdentifier)"
        output["install_identity"] = PermissionInstallIdentity.current()
        return output
    }

    private func permissionDetails(_ snapshot: PermissionSnapshot) -> [String: String] {
        [
            "microphone": snapshot.microphoneGranted ? "granted" : "missing",
            "accessibility": snapshot.accessibilityGranted ? "granted" : "missing",
            "input_monitoring": snapshot.inputMonitoringGranted ? "granted" : "missing"
        ]
    }

    private func otherRunningOmniVoiceApplications() -> [NSRunningApplication] {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: AppConstants.bundleIdentifier)
            .filter { $0.processIdentifier != currentPID && !$0.isTerminated }
    }

    @discardableResult
    private func resolveOtherInstancesBeforeListening() -> SingleInstanceResolution {
        let apps = otherRunningOmniVoiceApplications()
        guard !apps.isEmpty else {
            return SingleInstanceResolution(observedCount: 0, remainingCount: 0)
        }
        apps.forEach { app in
            if !app.terminate() {
                app.forceTerminate()
            }
        }
        var remainingApps = waitForOtherInstancesToExit(timeout: 1.2)
        if !remainingApps.isEmpty {
            remainingApps.forEach { $0.forceTerminate() }
            remainingApps = waitForOtherInstancesToExit(timeout: 0.4)
        }
        return SingleInstanceResolution(
            observedCount: apps.count,
            remainingCount: remainingApps.count
        )
    }

    private func waitForOtherInstancesToExit(timeout: TimeInterval) -> [NSRunningApplication] {
        let deadline = Date().addingTimeInterval(timeout)
        var remainingApps = otherRunningOmniVoiceApplications()
        while !remainingApps.isEmpty, Date() < deadline {
            let nextCheck = Date().addingTimeInterval(0.05)
            RunLoop.current.run(mode: .default, before: min(nextCheck, deadline))
            remainingApps = otherRunningOmniVoiceApplications()
        }
        return remainingApps
    }

    private func updateEventTapTriggerSuppression() {
        eventTap.setTriggerSuppressionEnabled(
            settings.listeningEnabled &&
            !globalStopActive &&
            (state == .idle || state == .recording)
        )
    }

    func start() {
        normalizeHUDStyleAvailability()
        syncLaunchAtLoginPreference(config.preferences.launchAtLogin, showWarningHUD: false)
        let startupPermissionSnapshot = PermissionChecker.snapshot()
        lastPermissionSnapshot = startupPermissionSnapshot
        let singleInstanceResolution = resolveOtherInstancesBeforeListening()
        let hasOtherInstanceConflict = !SingleInstanceLaunchPlanner.shouldAllowListening(
            resolution: singleInstanceResolution
        )
        stopReason = settings.stopReason
        let migratedStopReason = PermissionLegacyStopReasonMigrationPlanner.inferredStopReason(
            listeningEnabled: settings.listeningEnabled,
            storedStopReason: stopReason,
            didRunStartupPermissionGuide: settings.didRunStartupPermissionGuide
        )
        if migratedStopReason != stopReason {
            stopReason = migratedStopReason
            settings.stopReason = migratedStopReason
            recordLocalDiagnostic(stage: "legacy_permission_blocked_stop_reason_migrated")
        }
        let shouldStartStopped = AppSafetyPlanner.shouldStartInSafeMode(
            previousRuntimeActive: settings.runtimeActive
        )
        settings.runtimeActive = true
        if hasOtherInstanceConflict {
            globalStopActive = true
            stopReason = .manual
            settings.stopReason = .manual
            settings.listeningEnabled = false
            tapStatus = strings.stopped
            recordLocalDiagnostic(
                stage: "other_instance_detected",
                errorKind: "single_instance_conflict",
                details: diagnosticRuntimeDetails([
                    "other_instances_observed": "\(singleInstanceResolution.observedCount)",
                    "other_instances_remaining": "\(singleInstanceResolution.remainingCount)",
                    "listening_enabled": "false"
                ])
            )
        } else if singleInstanceResolution.observedCount > 0 {
            recordLocalDiagnostic(
                stage: "other_instance_terminated",
                details: diagnosticRuntimeDetails([
                    "other_instances_observed": "\(singleInstanceResolution.observedCount)",
                    "other_instances_remaining": "\(singleInstanceResolution.remainingCount)"
                ])
            )
        } else if shouldStartStopped {
            globalStopActive = true
            stopReason = .previousRunRecovery
            settings.stopReason = .previousRunRecovery
            settings.listeningEnabled = false
            tapStatus = strings.stoppedAfterPreviousRun
        } else if PermissionStartupAutoEnablePlanner.shouldAutoEnable(
            listeningEnabled: settings.listeningEnabled,
            stopReason: stopReason,
            current: startupPermissionSnapshot
        ) {
            globalStopActive = false
            stopReason = nil
            settings.stopReason = nil
            settings.listeningEnabled = true
            tapStatus = strings.listeningWithTrigger(settings.triggerKey)
            recordLocalDiagnostic(stage: "permissions_ready_startup_auto_reenabled")
        } else if !settings.listeningEnabled {
            applyPersistedStoppedState()
        } else if settings.listeningEnabled, !startupPermissionSnapshot.allRequiredGranted {
            enterPermissionBlockedStop(recordDiagnostic: false)
        }
        configureStatusItem()
        configWatcher.start()
        hud.setVisualStyle(settings.hudVisualStyle)
        actionPanel.setVisualStyle(settings.hudVisualStyle)
        if hasOtherInstanceConflict {
            rebuildMenu()
        } else if shouldStartStopped {
            recordLocalDiagnostic(
                stage: "global_stop_enabled",
                errorKind: "previous_runtime_active",
                details: diagnosticRuntimeDetails(["auto_insert_paused": "true", "listening_enabled": "false"])
            )
        } else {
            rebuildMenu()
        }
        if settings.listeningEnabled {
            startListening(showFailureHUD: false)
        }
        scheduleLatencyChecks()
        Task { await runStartupPermissionGuideIfNeeded() }
        Task { await refreshModels(showStatus: false) }
    }

    func stop() {
        maxRecordingTimer?.invalidate()
        resetListeningHUDRevealState()
        latencyTimer?.invalidate()
        latencyTimer = nil
        configWatcher.stop()
        stopPermissionReadinessPolling()
        stopPermissionDriftMonitoring()
        transcriptionTask?.cancel()
        recordingSource.cancel()
        hud.hide()
        actionPanel.cancel()
        recordingStartDate = nil
        eventTap.setCancellationActive(false)
        eventTap.setTriggerSuppressionEnabled(false)
        eventTap.stop()
        cancelTriggerCapture(restartListening: false)
        settings.runtimeActive = false
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusItem() {
        statusItem.length = 23
        if let button = statusItem.button {
            button.image = makeStatusBarImage()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyUpOrDown
            button.toolTip = AppConstants.productName
        }
        statusItem.menu = NSMenu(title: AppConstants.productName)
        statusItem.menu?.delegate = self
    }

    private func makeStatusBarImage() -> NSImage {
        let size = NSSize(width: 17, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()

        let barWidth: CGFloat = 1.85
        let spacing: CGFloat = 0.85
        let heights: [CGFloat] = [7.0, 12.0, 8.2, 4.9, 8.6, 5.9]
        let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * spacing
        var x = (size.width - totalWidth) / 2

        for height in heights {
            let rect = NSRect(
                x: x,
                y: (size.height - height) / 2,
                width: barWidth,
                height: height
            )
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            x += barWidth + spacing
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    func menuWillOpen(_ menu: NSMenu) {
        handlePermissionReadiness(PermissionChecker.snapshot())
        rebuildMenu()
    }

    private func rebuildMenu() {
        let permissionSnapshot = PermissionChecker.snapshot()
        let displayConfig = config.resolvingSource(using: sourceLatencyResults)
        let menu = NSMenu(title: AppConstants.productName)
        menu.delegate = self

        menu.addItem(item(
            title: globalStopActive || !settings.listeningEnabled ? strings.reenable : strings.stop,
            action: #selector(toggleGlobalStop),
            tooltip: strings.tooltip(.globalStop)
        ))
        menu.addItem(disabledItem("\(strings.statusPrefix): \(statusTitle)"))
        menu.addItem(permissionSummaryItem(permissionSnapshot))
        menu.addItem(item(title: strings.requestAllPermissions, action: #selector(requestAllPermissions), tooltip: strings.tooltip(.requestAllPermissions)))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(disabledItem("\(strings.baseURLPrefix): \(displayConfig.redactedStatus.baseURLHost)"))
        menu.addItem(disabledItem("\(strings.apiKeyPrefix): \(strings.apiKeyStatus(displayConfig))"))
        menu.addItem(disabledItem(MenuTitleFormatter.model(settings.selectedModel, uiLanguage: settings.uiLanguage)))
        menu.addItem(disabledItem(strings.configSource(displayConfig)))
        for warning in config.warnings {
            menu.addItem(disabledItem(strings.configWarning(warning)))
        }
        if let lastConfigHotReloadMessage {
            menu.addItem(disabledItem(lastConfigHotReloadMessage))
        }
        menu.addItem(submenuItem(strings.configurationTitle(displayConfig), submenu: configurationMenu(), tooltip: strings.tooltip(.configuration)))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(submenuItem(MenuTitleFormatter.language(settings.uiLanguage, uiLanguage: settings.uiLanguage), submenu: languageMenu()))
        let styleDescriptor = currentStyleDescriptor
        menu.addItem(submenuItem(
            MenuTitleFormatter.style(styleDescriptor, uiLanguage: settings.uiLanguage),
            submenu: styleMenu(),
            tooltip: tooltip(for: styleDescriptor)
        ))
        menu.addItem(submenuItem(
            strings.keywordHintsTitle(enabled: settings.keywordHintsEnabled, selectedCount: selectedKeywordGroupCount),
            submenu: keywordHintsMenu(),
            tooltip: strings.tooltip(.keywordHints)
        ))
        menu.addItem(submenuItem(MenuTitleFormatter.trigger(settings.triggerKey, uiLanguage: settings.uiLanguage), submenu: triggerMenu()))
        menu.addItem(submenuItem(
            MenuTitleFormatter.recordingDuration(
                min: settings.minRecordingDuration,
                max: settings.maxRecordingDuration,
                uiLanguage: settings.uiLanguage
            ),
            submenu: durationMenu()
        ))
        menu.addItem(NSMenuItem.separator())

        let launchAtLogin = item(title: strings.launchAtLogin, action: #selector(toggleLaunchAtLogin))
        launchAtLogin.state = LaunchAtLoginController.status() == .enabled ? .on : .off
        launchAtLogin.toolTip = strings.tooltip(.launchAtLogin)
        menu.addItem(launchAtLogin)
        let autoInsert = item(title: strings.autoInsert, action: #selector(toggleAutoInsert))
        autoInsert.state = settings.autoInsert ? .on : .off
        autoInsert.toolTip = strings.tooltip(.autoInsert)
        menu.addItem(autoInsert)
        menu.addItem(submenuItem(strings.displayHints, submenu: displayHintsMenu(), tooltip: strings.tooltip(.displayHints)))
        if let lastLaunchAtLoginError {
            menu.addItem(disabledItem(lastLaunchAtLoginError))
        }
        menu.addItem(submenuItem(strings.permissionManagement, submenu: permissionsMenu(snapshot: permissionSnapshot)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(title: strings.restart, action: #selector(restartApp)))
        menu.addItem(item(title: strings.quit, action: #selector(quit)))

        statusItem.menu = menu
    }

    private var statusTitle: String {
        if globalStopActive {
            return strings.stopped
        }
        switch state {
        case .idle:
            return strings.statusIdle(
                listeningEnabled: settings.listeningEnabled,
                tapStatus: tapStatus ?? strings.listeningWithTrigger(settings.triggerKey)
            )
        case .recording:
            return strings.statusRecording()
        case .transcribing:
            return strings.statusTranscribing()
        }
    }

    private var connectionCheckTitle: String {
        if isTestingConnection {
            return strings.connectionCheckRunning()
        }
        if let lastTestConnectionResult {
            return strings.connectionCheckMessage(lastTestConnectionResult)
        }
        return strings.connectionCheckDefault()
    }

    private func modelMenu() -> NSMenu {
        let menu = NSMenu(title: "Model")
        for model in AllowedSpeechModel.allCases {
            let menuItem = item(title: model.rawValue, action: #selector(selectModel(_:)))
            menuItem.representedObject = model.rawValue
            menuItem.state = model == settings.selectedModel ? .on : .off
            menuItem.isEnabled = availableModels.contains(model) || availableModels.isEmpty
            menu.addItem(menuItem)
        }
        return menu
    }

    private func languageMenu() -> NSMenu {
        let menu = NSMenu(title: strings.uiLanguageTitle(settings.uiLanguage))
        for language in UILanguage.allCases {
            let menuItem = item(title: language.displayName, action: #selector(selectLanguage(_:)))
            menuItem.representedObject = language.rawValue
            menuItem.state = language == settings.uiLanguage ? .on : .off
            menu.addItem(menuItem)
        }
        return menu
    }

    private func styleMenu() -> NSMenu {
        let selected = currentStyleDescriptor.selection
        let menu = NSMenu(title: strings.styleTitle(currentStyleDescriptor))
        for style in TranscriptionStyle.menuOrder {
            let descriptor = TranscriptionStyleResolver.builtInDescriptor(style)
            let menuItem = item(title: strings.styleMenuItem(descriptor), action: #selector(selectStyle(_:)))
            menuItem.representedObject = descriptor.selection.rawValue
            menuItem.state = descriptor.selection == selected ? .on : .off
            menuItem.toolTip = tooltip(for: descriptor)
            menu.addItem(menuItem)
        }
        if !config.customStyles.isEmpty {
            menu.addItem(NSMenuItem.separator())
            for custom in config.customStyles {
                let descriptor = TranscriptionStyleResolver.customDescriptor(custom)
                let menuItem = item(title: strings.styleMenuItem(descriptor), action: #selector(selectStyle(_:)))
                menuItem.representedObject = descriptor.selection.rawValue
                menuItem.state = descriptor.selection == selected ? .on : .off
                menuItem.toolTip = tooltip(for: descriptor)
                menu.addItem(menuItem)
            }
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(
            title: strings.editCustomStyles,
            action: #selector(openConfigFile),
            tooltip: strings.tooltip(.customStyles)
        ))
        return menu
    }

    private func keywordHintsMenu() -> NSMenu {
        let selectedIDs = Set(settings.enabledKeywordGroupIDs)
        let menu = NSMenu(title: strings.keywordHints)
        let enableItem = item(
            title: strings.enableKeywordHints,
            action: #selector(toggleKeywordHints),
            tooltip: strings.tooltip(.keywordHints)
        )
        enableItem.state = settings.keywordHintsEnabled ? .on : .off
        menu.addItem(enableItem)
        menu.addItem(NSMenuItem.separator())

        if config.keywordGroups.isEmpty {
            menu.addItem(disabledItem(strings.noKeywordGroups))
        } else {
            for group in config.keywordGroups {
                let menuItem = item(
                    title: strings.keywordGroupMenuItem(group),
                    action: #selector(toggleKeywordGroup(_:)),
                    tooltip: group.localizedDescription(in: settings.uiLanguage) ?? strings.tooltip(.keywordHints)
                )
                menuItem.representedObject = group.id
                menuItem.state = selectedIDs.contains(group.id) ? .on : .off
                menuItem.isEnabled = settings.keywordHintsEnabled
                menu.addItem(menuItem)
            }
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(
            title: strings.editKeywords,
            action: #selector(openConfigFile),
            tooltip: strings.tooltip(.keywordHints)
        ))
        return menu
    }

    private func triggerMenu() -> NSMenu {
        let menu = NSMenu(title: strings.triggerTitle(settings.triggerKey))
        let captureView = TriggerCaptureMenuView(
            strings: strings,
            selectedTriggerLabel: strings.triggerLabel(settings.triggerKey),
            onBegin: { [weak self] view in
                self?.beginTriggerCapture(view: view)
            }
        )
        triggerCaptureView = captureView
        let captureItem = NSMenuItem()
        captureItem.view = captureView
        menu.addItem(captureItem)
        menu.addItem(NSMenuItem.separator())
        addTriggerItem(TriggerKey.fnGlobe, to: menu)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(submenuItem(settings.uiLanguage == .chinese ? "功能键" : "Function Keys", submenu: triggerSubmenu(TriggerKey.functionKeys)))
        menu.addItem(submenuItem(settings.uiLanguage == .chinese ? "修饰键" : "Modifiers", submenu: triggerSubmenu(TriggerKey.modifierKeys)))
        menu.addItem(NSMenuItem.separator())
        addTriggerItem(TriggerKey.capsLock, to: menu)
        return menu
    }

    private func triggerSubmenu(_ triggers: [TriggerKey]) -> NSMenu {
        let menu = NSMenu()
        for trigger in triggers {
            addTriggerItem(trigger, to: menu)
        }
        return menu
    }

    private func addTriggerItem(_ trigger: TriggerKey, to menu: NSMenu) {
        let menuItem = item(title: strings.triggerLabel(trigger), action: #selector(selectTrigger(_:)))
        menuItem.representedObject = trigger.identifier
        menuItem.state = trigger == settings.triggerKey ? .on : .off
        menu.addItem(menuItem)
    }

    private func durationMenu() -> NSMenu {
        let menu = NSMenu(title: strings.recordingDurationTitle(min: settings.minRecordingDuration, max: settings.maxRecordingDuration))
        menu.addItem(disabledItem(strings.minRecordingDuration))
        for duration in MinRecordingDuration.allCases {
            let menuItem = item(title: duration.displayName, action: #selector(selectMinDuration(_:)))
            menuItem.representedObject = duration.rawValue
            menuItem.state = duration == settings.minRecordingDuration ? .on : .off
            menu.addItem(menuItem)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(disabledItem(strings.maxRecordingDuration))
        for duration in MaxRecordingDuration.allCases {
            let menuItem = item(title: duration.displayName, action: #selector(selectDuration(_:)))
            menuItem.representedObject = duration.rawValue
            menuItem.state = duration == settings.maxRecordingDuration ? .on : .off
            menu.addItem(menuItem)
        }
        return menu
    }

    private func hudStyleMenu() -> NSMenu {
        let menu = NSMenu(title: strings.hudStyle)
        for style in HUDVisualStyleAvailability.availableStyles() {
            let menuItem = item(title: style.displayName(in: settings.uiLanguage), action: #selector(selectHUDStyle(_:)))
            menuItem.representedObject = style.rawValue
            menuItem.state = style == settings.hudVisualStyle ? .on : .off
            menu.addItem(menuItem)
        }
        return menu
    }

    private func hudMessageDurationMenu() -> NSMenu {
        let menu = NSMenu(title: strings.hudMessageDuration)
        for duration in HUDMessageDuration.allCases {
            let menuItem = item(title: duration.displayName, action: #selector(selectHUDMessageDuration(_:)), tooltip: strings.tooltip(.hudMessageDuration))
            menuItem.representedObject = duration.rawValue
            menuItem.state = duration == settings.hudMessageDuration ? .on : .off
            menu.addItem(menuItem)
        }
        return menu
    }

    private func hudRevealDelayMenu() -> NSMenu {
        let menu = NSMenu(title: strings.hudRevealDelay)
        for delay in HUDRevealDelay.allCases {
            let menuItem = item(title: delay.displayName(in: settings.uiLanguage), action: #selector(selectHUDRevealDelay(_:)), tooltip: strings.tooltip(.hudRevealDelay))
            menuItem.representedObject = delay.rawValue
            menuItem.state = delay == settings.hudRevealDelay ? .on : .off
            menu.addItem(menuItem)
        }
        return menu
    }

    private func displayHintsMenu() -> NSMenu {
        let menu = NSMenu(title: strings.displayHints)
        menu.addItem(submenuItem(
            MenuTitleFormatter.hudStyle(settings.hudVisualStyle, uiLanguage: settings.uiLanguage),
            submenu: hudStyleMenu()
        ))
        menu.addItem(submenuItem(
            strings.hudMessageDurationTitle(settings.hudMessageDuration),
            submenu: hudMessageDurationMenu(),
            tooltip: strings.tooltip(.hudMessageDuration)
        ))
        menu.addItem(submenuItem(
            strings.hudRevealDelayTitle(settings.hudRevealDelay),
            submenu: hudRevealDelayMenu(),
            tooltip: strings.tooltip(.hudRevealDelay)
        ))
        return menu
    }

    private func configurationMenu() -> NSMenu {
        let menu = NSMenu(title: strings.configuration)
        let displayConfig = config.resolvingSource(using: sourceLatencyResults)
        menu.addItem(disabledItem(strings.configSource(displayConfig)))
        menu.addItem(submenuItem(strings.apiSourceTitle(config), submenu: apiSourceMenu()))
        menu.addItem(submenuItem(MenuTitleFormatter.model(settings.selectedModel, uiLanguage: settings.uiLanguage), submenu: modelMenu()))
        menu.addItem(submenuItem(strings.latencyIntervalTitle(config.latencySettings.interval), submenu: latencyIntervalMenu()))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(title: strings.openConfigFile, action: #selector(openConfigFile), tooltip: strings.tooltip(.configuration)))
        menu.addItem(item(title: strings.reloadConfig, action: #selector(reloadConfig), tooltip: strings.tooltip(.reloadConfig)))
        menu.addItem(item(title: strings.refreshModels, action: #selector(refreshModelsAction), tooltip: strings.tooltip(.refreshModels)))
        menu.addItem(item(title: connectionCheckTitle, action: #selector(checkConnectionAndLatency), tooltip: strings.tooltip(.connectionCheck)))
        return menu
    }

    private func apiSourceMenu() -> NSMenu {
        let menu = NSMenu(title: strings.apiSource)
        let autoItem = item(
            title: strings.autoAPISourceMenuItem(resolvedSourceID: config.resolvedSourceID),
            action: #selector(selectAPISource(_:)),
            tooltip: strings.tooltip(.apiSourceAuto)
        )
        autoItem.representedObject = MimoConfig.autoSourceID
        autoItem.state = config.activeSourceID == MimoConfig.autoSourceID ? .on : .off
        menu.addItem(autoItem)
        menu.addItem(NSMenuItem.separator())
        for source in config.sourceSummaries {
            let menuItem = item(
                title: strings.apiSourceMenuItem(source, latency: sourceLatencyResults[source.id]),
                action: #selector(selectAPISource(_:)),
                tooltip: strings.tooltip(.configuration)
            )
            menuItem.representedObject = source.id
            menuItem.state = source.id == config.activeSourceID ? .on : .off
            menu.addItem(menuItem)
        }
        if config.sourceSummaries.isEmpty {
            menu.addItem(disabledItem(strings.configWarning("Config file missing")))
        }
        return menu
    }

    private func latencyIntervalMenu() -> NSMenu {
        let menu = NSMenu(title: strings.latencyInterval)
        for interval in ConfigLatencyInterval.allCases {
            let menuItem = item(title: strings.latencyIntervalLabel(interval), action: #selector(selectLatencyInterval(_:)), tooltip: strings.tooltip(.latency))
            menuItem.representedObject = interval.rawValue
            menuItem.state = interval == config.latencySettings.interval ? .on : .off
            menu.addItem(menuItem)
        }
        return menu
    }

    private func permissionsMenu(snapshot: PermissionSnapshot) -> NSMenu {
        let menu = NSMenu(title: strings.permissions)
        menu.addItem(permissionSummaryItem(snapshot))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(title: strings.requestAllPermissions, action: #selector(requestAllPermissions), tooltip: strings.tooltip(.requestAllPermissions)))
        menu.addItem(item(title: strings.requestMicrophone, action: #selector(requestMicrophonePermission), tooltip: strings.tooltip(.requestMicrophone)))
        menu.addItem(item(title: strings.requestAccessibility, action: #selector(requestAccessibilityPermission), tooltip: strings.tooltip(.requestAccessibility)))
        menu.addItem(item(title: strings.requestInputMonitoring, action: #selector(requestInputMonitoringPermission), tooltip: strings.tooltip(.requestInputMonitoring)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(title: strings.openMicrophoneSettings, action: #selector(openMicrophoneSettings)))
        menu.addItem(item(title: strings.openAccessibilitySettings, action: #selector(openAccessibilitySettings)))
        menu.addItem(item(title: strings.openInputMonitoringSettings, action: #selector(openInputMonitoringSettings)))
        return menu
    }

    private func permissionEntries(_ snapshot: PermissionSnapshot) -> [(label: String, granted: Bool)] {
        if settings.uiLanguage == .chinese {
            return [
                ("麦克风", snapshot.microphoneGranted),
                ("辅助功能", snapshot.accessibilityGranted),
                ("输入监控", snapshot.inputMonitoringGranted)
            ]
        }
        return [
            ("Microphone", snapshot.microphoneGranted),
            ("Accessibility", snapshot.accessibilityGranted),
            ("Input Monitoring", snapshot.inputMonitoringGranted)
        ]
    }

    private func permissionSummaryItem(_ snapshot: PermissionSnapshot) -> NSMenuItem {
        let item = NSMenuItem(title: strings.permissionSummary(snapshot), action: nil, keyEquivalent: "")
        item.attributedTitle = permissionSummaryAttributedString(snapshot)
        item.toolTip = strings.permissionUsageTooltip
        item.isEnabled = true
        return item
    }

    private func permissionSummaryAttributedString(_ snapshot: PermissionSnapshot) -> NSAttributedString {
        let output = NSMutableAttributedString(string: settings.uiLanguage == .chinese ? "权限：" : "Permissions: ", attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor
        ])
        for (index, entry) in permissionEntries(snapshot).enumerated() {
            if index > 0 {
                output.append(NSAttributedString(string: " · ", attributes: [
                    .font: NSFont.menuFont(ofSize: 0),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]))
            }
            output.append(permissionStatusAttributedString(
                text: strings.permissionDetail(entry.label, granted: entry.granted),
                granted: entry.granted
            ))
        }
        return output
    }

    private func permissionStatusAttributedString(text: String, granted: Bool) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: granted
                ? NSColor(calibratedRed: 0.23, green: 0.58, blue: 0.35, alpha: 1.0)
                : NSColor(calibratedRed: 0.78, green: 0.25, blue: 0.22, alpha: 1.0)
        ])
    }

    private func tooltip(for descriptor: TranscriptionStyleDescriptor) -> String {
        if let customTooltip = descriptor.localizedTooltip(in: settings.uiLanguage) {
            return customTooltip
        }
        switch descriptor.builtInStyle {
        case .concise:
            return strings.tooltip(.styleConcise)
        case .verbatim:
            return strings.tooltip(.styleVerbatim)
        case .codeFaithful:
            return strings.tooltip(.styleTechnical)
        case .rewrite:
            return strings.tooltip(.styleRewrite)
        case nil:
            return strings.tooltip(.customStyles)
        }
    }

    private func item(title: String, action: Selector?, tooltip: String? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        menuItem.toolTip = tooltip
        return menuItem
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.isEnabled = false
        return menuItem
    }

    private func submenuItem(_ title: String, submenu: NSMenu, tooltip: String? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.submenu = submenu
        menuItem.toolTip = tooltip
        return menuItem
    }

    @objc private func toggleGlobalStop() {
        if globalStopActive || !settings.listeningEnabled {
            reenable()
        } else {
            stopAllFeatures()
        }
    }

    @objc private func toggleAutoInsert() {
        settings.autoInsert.toggle()
        _ = persistCurrentPreferences()
        rebuildMenu()
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let model = AllowedSpeechModel(rawValue: raw) else { return }
        settings.selectedModel = model
        _ = persistCurrentPreferences()
        rebuildMenu()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let language = UILanguage(rawValue: raw) else { return }
        settings.uiLanguage = language
        _ = persistCurrentPreferences()
        if settings.listeningEnabled {
            tapStatus = eventTap.isRunning ? strings.listeningWithTrigger(settings.triggerKey) : strings.listeningUnavailable()
        }
        rebuildMenu()
        applyPendingConfigHotReloadIfNeeded()
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        settings.transcriptionStyleSelection = TranscriptionStyleSelection(rawValue: raw)
        _ = persistCurrentPreferences()
        rebuildMenu()
    }

    @objc private func toggleKeywordHints() {
        settings.keywordHintsEnabled.toggle()
        _ = persistCurrentPreferences()
        rebuildMenu()
    }

    @objc private func toggleKeywordGroup(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              config.keywordGroups.contains(where: { $0.id == id }) else { return }
        var ids = settings.enabledKeywordGroupIDs
        if ids.contains(id) {
            ids.removeAll { $0 == id }
        } else {
            ids.append(id)
        }
        settings.enabledKeywordGroupIDs = ids.filter(KeywordGroupValidator.isValidID)
        _ = persistCurrentPreferences()
        rebuildMenu()
    }

    @objc private func selectTrigger(_ sender: NSMenuItem) {
        let trigger = TriggerKey.candidate(identifier: sender.representedObject as? String)
        cancelTriggerCapture(restartListening: false)
        applyTriggerSelection(trigger)
    }

    private func applyTriggerSelection(_ trigger: TriggerKey) {
        settings.triggerKey = trigger
        eventTap.update(triggerKey: trigger)
        if settings.listeningEnabled, !globalStopActive {
            startListening(showFailureHUD: true)
        }
        _ = persistCurrentPreferences()
        rebuildMenu()
    }

    private func beginTriggerCapture(view: TriggerCaptureMenuView) {
        cancelTriggerCapture(updateView: false, restartListening: false)
        let decision = TriggerCaptureSessionPlanner.begin(
            listeningEnabled: settings.listeningEnabled,
            normalTapRunning: eventTap.isRunning
        )
        triggerCapturePausedListening = decision.shouldPauseNormalTap
        if decision.shouldPauseNormalTap {
            eventTap.stop()
        }
        triggerCaptureView = view
        view.beginCapture()
        guard triggerCapture.start() else {
            view.showRejected(strings.inputMonitoringManual)
            hud.showWarningStatus(strings.inputMonitoringManual, duration: warningDuration)
            cancelTriggerCapture(updateView: false, restartListening: true)
            return
        }
        triggerCaptureTimeout = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.cancelTriggerCapture()
            }
        }
    }

    private func handleTriggerCaptureSignal(_ signal: TriggerCaptureSignal) {
        guard triggerCapture.isRunning else { return }
        switch signal {
        case .captured(let candidate):
            let view = triggerCaptureView
            cancelTriggerCapture(updateView: false, restartListening: false)
            view?.showSelected(strings.triggerLabel(candidate))
            applyTriggerSelection(candidate)
        case .cancelled:
            cancelTriggerCapture()
        case .rejected:
            triggerCaptureView?.showRejected(strings.triggerRecordingRejected)
        case .failed:
            triggerCaptureView?.showRejected(strings.inputMonitoringManual)
            hud.showWarningStatus(strings.inputMonitoringManual, duration: warningDuration)
            cancelTriggerCapture(updateView: false, restartListening: true)
        case .emergencyRescue:
            performEmergencyRescueExit()
        }
    }

    private func cancelTriggerCapture(updateView: Bool = true, restartListening: Bool = true) {
        if triggerCapture.isRunning {
            triggerCapture.stop()
        }
        triggerCaptureTimeout?.invalidate()
        triggerCaptureTimeout = nil
        if updateView {
            triggerCaptureView?.endCapture()
        }
        triggerCaptureView = nil
        let shouldRestartListening = TriggerCaptureSessionPlanner.finish(
            pausedNormalTap: triggerCapturePausedListening,
            restartListening: restartListening,
            listeningEnabled: settings.listeningEnabled && !globalStopActive
        ).shouldRestoreNormalTap
        triggerCapturePausedListening = false
        if shouldRestartListening {
            startListening(showFailureHUD: false)
        }
    }

    @objc private func selectDuration(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Int else { return }
        settings.maxRecordingDuration = MaxRecordingDuration.safeSelection(seconds)
        eventTap.updateWatchdogTimeout(seconds: TimeInterval(settings.maxRecordingDuration.rawValue + 5))
        _ = persistCurrentPreferences()
        rebuildMenu()
    }

    @objc private func selectMinDuration(_ sender: NSMenuItem) {
        guard let milliseconds = sender.representedObject as? Int else { return }
        settings.minRecordingDuration = MinRecordingDuration.safeSelection(milliseconds)
        _ = persistCurrentPreferences()
        rebuildMenu()
    }

    @objc private func selectHUDStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        settings.hudVisualStyle = HUDVisualStyleAvailability.sanitizedSelection(HUDVisualStyle.safeSelection(raw))
        hud.setVisualStyle(settings.hudVisualStyle)
        actionPanel.setVisualStyle(settings.hudVisualStyle)
        _ = persistCurrentPreferences()
        rebuildMenu()
    }

    @objc private func selectHUDMessageDuration(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Int else { return }
        settings.hudMessageDuration = HUDMessageDuration.safeSelection(seconds)
        _ = persistCurrentPreferences()
        rebuildMenu()
    }

    @objc private func selectHUDRevealDelay(_ sender: NSMenuItem) {
        guard let milliseconds = sender.representedObject as? Int else { return }
        settings.hudRevealDelay = HUDRevealDelay.safeSelection(milliseconds)
        _ = persistCurrentPreferences()
        rebuildMenu()
    }

    @objc private func toggleLaunchAtLogin() {
        let enable = LaunchAtLoginController.status() != .enabled
        do {
            try LaunchAtLoginController.setEnabled(enable)
            lastLaunchAtLoginError = nil
        } catch {
            lastLaunchAtLoginError = sanitizedMessage(for: error)
            hud.showWarningStatus(lastLaunchAtLoginError ?? strings.operationFailed, duration: warningDuration)
        }
        _ = persistCurrentPreferences()
        rebuildMenu()
    }

    @objc private func reloadConfig() {
        config = loadConfig()
        applyLoadedConfigPreferences(config, syncLaunchAtLogin: true)
        client = makeClient(config: config)
        lastTestConnectionResult = nil
        lastConfigHotReloadMessage = nil
        scheduleLatencyChecks()
        hud.showTransientStatus(strings.configReloaded, duration: warningDuration)
        rebuildMenu()
    }

    private func handleConfigFileChanged() {
        if let ignoreUntil = ignoreConfigFileChangesUntil {
            if Date() < ignoreUntil {
                return
            }
            ignoreConfigFileChangesUntil = nil
        }
        guard state == .idle else {
            pendingConfigHotReload = true
            return
        }
        applyConfigHotReload()
    }

    private func markInternalConfigWrite() {
        ignoreConfigFileChangesUntil = Date().addingTimeInterval(2)
    }

    private func applyPendingConfigHotReloadIfNeeded() {
        guard pendingConfigHotReload, state == .idle else { return }
        pendingConfigHotReload = false
        applyConfigHotReload()
    }

    private func applyConfigHotReload() {
        switch configLoader.loadValidConfigWithoutRepair() {
        case .valid(let loaded):
            lastInvalidConfigFingerprint = nil
            lastConfigHotReloadMessage = nil
            config = loaded
            applyLoadedConfigPreferences(loaded, syncLaunchAtLogin: true)
            client = makeClient(config: config)
            lastTestConnectionResult = nil
            scheduleLatencyChecks()
            recordLocalDiagnostic(
                stage: "config_hot_reload_applied",
                details: [
                    "keyword_groups": "\(loaded.keywordGroups.count)",
                    "enabled_keyword_groups": "\(loaded.preferences.enabledKeywordGroupIDs.count)"
                ]
            )
            hud.showTransientStatus(strings.configHotReloaded, duration: warningDuration)
            rebuildMenu()
        case .invalid(let issues):
            let fingerprint = invalidConfigFingerprint()
            guard fingerprint != lastInvalidConfigFingerprint else { return }
            lastInvalidConfigFingerprint = fingerprint
            let message: String
            if let exportURL = configLoader.exportCurrentConfigSnapshot(config, uiLanguage: settings.uiLanguage) {
                message = strings.configHotReloadInvalidExported(exportURL.path)
                recordLocalDiagnostic(
                    stage: "config_hot_reload_invalid",
                    errorKind: "invalid_config",
                    details: [
                        "issues": issues.joined(separator: ","),
                        "export_path": exportURL.path
                    ]
                )
            } else {
                message = strings.configWarning("Config warning: config.jsonc could not be read")
                recordLocalDiagnostic(
                    stage: "config_hot_reload_invalid",
                    errorKind: "invalid_config_export_failed",
                    details: ["issues": issues.joined(separator: ",")]
                )
            }
            lastConfigHotReloadMessage = message
            hud.showWarningStatus(message, duration: warningDuration)
            rebuildMenu()
        }
    }

    private func invalidConfigFingerprint() -> String {
        guard let data = try? Data(contentsOf: configLoader.configFileURL) else {
            return "missing"
        }
        return "\(data.count):\(data.hashValue)"
    }

    @objc private func selectAPISource(_ sender: NSMenuItem) {
        guard let sourceID = sender.representedObject as? String else { return }
        markInternalConfigWrite()
        _ = configLoader.saveActiveSource(sourceID, uiLanguage: settings.uiLanguage)
        config = loadConfig()
        client = makeClient(config: config)
        lastTestConnectionResult = nil
        scheduleLatencyChecks()
        rebuildMenu()
    }

    @objc private func selectLatencyInterval(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? Int else { return }
        let interval = ConfigLatencyInterval.safeSelection(rawValue)
        markInternalConfigWrite()
        _ = configLoader.saveLatencyInterval(interval, uiLanguage: settings.uiLanguage)
        config = loadConfig()
        scheduleLatencyChecks()
        rebuildMenu()
    }

    @objc private func openConfigFile() {
        config = configLoader.ensureValidConfig(uiLanguage: settings.uiLanguage)
        guard configLoader.fileManager.fileExists(atPath: configLoader.configFileURL.path) else {
            hud.showWarningStatus(strings.configFileOpenFailed, duration: warningDuration)
            return
        }
        openConfigFileUsingPlan(configLoader.configFileURL, plan: ConfigFileOpenPlanner.plan())
    }

    private func openConfigFileUsingPlan(_ fileURL: URL, plan: ConfigFileOpenPlan) {
        switch plan.method {
        case let .applicationBundle(appURL, displayName):
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: configuration) { [weak self] _, error in
                guard let self else { return }
                DispatchQueue.main.async {
                    if error == nil {
                        self.hud.showTransientStatus(self.strings.configFileOpenedInEditor(displayName), duration: self.warningDuration)
                    } else {
                        self.openConfigFileWithDefaultApp(fileURL, noEditorFound: true)
                    }
                }
            }
        case let .command(commandURL, displayName):
            do {
                let process = Process()
                process.executableURL = commandURL
                process.arguments = [fileURL.path]
                try process.run()
                hud.showTransientStatus(strings.configFileOpenedInEditor(displayName), duration: warningDuration)
            } catch {
                openConfigFileWithDefaultApp(fileURL, noEditorFound: true)
            }
        case .systemDefault:
            openConfigFileWithDefaultApp(fileURL, noEditorFound: true)
        }
    }

    private func openConfigFileWithDefaultApp(_ fileURL: URL, noEditorFound: Bool) {
        if NSWorkspace.shared.open(fileURL) {
            let message = noEditorFound ? strings.configFileOpenedWithDefaultApp : strings.configFileOpened
            hud.showTransientStatus(message, duration: warningDuration)
        } else {
            hud.showWarningStatus(strings.configFileOpenFailed, duration: warningDuration)
        }
    }

    @objc private func refreshModelsAction() {
        Task { await refreshModels(showStatus: true) }
    }

    private func scheduleLatencyChecks() {
        latencyTimer?.invalidate()
        latencyTimer = nil
        guard config.latencySettings.interval != .off else { return }
        Task { await refreshSourceLatencies(showStatus: false) }
        guard let seconds = config.latencySettings.interval.seconds else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshSourceLatencies(showStatus: false)
            }
        }
        latencyTimer = timer
    }

    private func refreshSourceLatencies(showStatus: Bool) async {
        guard !config.sources.isEmpty else {
            if showStatus {
                hud.showWarningStatus(strings.configWarning("Config file missing"), duration: warningDuration)
            }
            return
        }
        var measurements: [String: SourceLatencyMeasurement] = [:]
        for source in config.sources {
            guard let sourceConfig = config.selectingSource(source.id) else { continue }
            let measurement = await MimoAPIClient(config: sourceConfig).measureModelsLatency()
            measurements[source.id] = measurement
            recordLocalDiagnostic(
                stage: "source_latency_measured",
                errorKind: measurement.errorKind,
                details: [
                    "source_id": source.id,
                    "host": source.baseURL.host ?? source.baseURL.absoluteString,
                    "http_status": measurement.httpStatus.map(String.init) ?? "none",
                    "milliseconds": measurement.milliseconds.map(String.init) ?? "none",
                    "reachable": measurement.reachable ? "true" : "false",
                    "speech_models": measurement.allowedSpeechModels.map(\.rawValue).joined(separator: ",")
                ]
            )
        }
        sourceLatencyResults.merge(measurements) { _, new in new }
        let resolved = config.resolvingSource(using: sourceLatencyResults)
        client = makeClient(config: resolved)
        if let measurement = sourceLatencyResults[resolved.resolvedSourceID], !measurement.allowedSpeechModels.isEmpty {
            availableModels = measurement.allowedSpeechModels
        }
        if showStatus {
            hud.showTransientStatus(strings.connectionLatencyCompleted, duration: warningDuration)
        }
        rebuildMenu()
        applyPendingConfigHotReloadIfNeeded()
    }

    @objc private func checkConnectionAndLatency() {
        isTestingConnection = true
        rebuildMenu()
        Task {
            await refreshSourceLatencies(showStatus: false)
            client = makeClient(config: config.resolvingSource(using: sourceLatencyResults))
            let result = await client.testConnection(selectedModel: settings.selectedModel, runAudioProbe: false)
            lastTestConnectionResult = result
            isTestingConnection = false
            let message = strings.connectionCheckMessage(result)
            if result.modelsReachable, result.selectedModelAllowed {
                hud.showTransientStatus(message, duration: warningDuration)
            } else {
                hud.showWarningStatus(message, duration: warningDuration)
            }
            rebuildMenu()
        }
    }

    private func stopAllFeatures() {
        let priorState = String(describing: state)
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil
        resetListeningHUDRevealState()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        recordingSource.cancel()
        eventTap.setCancellationActive(false)
        eventTap.stop()
        hud.hide()
        actionPanel.cancel()
        recordingFocus = nil
        recordingStartDate = nil
        pendingTranscription = nil
        stopPermissionReadinessPolling()
        stopPermissionDriftMonitoring()
        state = .idle
        settings.listeningEnabled = false
        globalStopActive = true
        stopReason = .manual
        settings.stopReason = .manual
        eventTap.setTriggerSuppressionEnabled(false)
        tapStatus = strings.stopped
        hud.showTransientStatus(strings.stopped, duration: warningDuration)
        recordLocalDiagnostic(
            stage: "global_stop",
            errorKind: "manual_stop",
            details: [
                "previous_state": priorState,
                "listening_enabled": "false",
                "auto_insert_paused": "true"
            ]
        )
        rebuildMenu()
    }

    private func reenable() {
        globalStopActive = false
        stopReason = nil
        settings.stopReason = nil
        stopPermissionReadinessPolling()
        settings.listeningEnabled = true
        startListening(showFailureHUD: true)
        if !globalStopActive {
            hud.showTransientStatus(strings.reenabled, duration: warningDuration)
            recordLocalDiagnostic(stage: "global_reenabled", details: ["auto_insert_paused": "false"])
        }
        rebuildMenu()
        applyPendingConfigHotReloadIfNeeded()
    }

    @objc private func requestAllPermissions() {
        Task { await runPermissionGuide(isManualRequest: true) }
    }

    @objc private func requestMicrophonePermission() {
        Task {
            _ = await PermissionChecker.requestMicrophone()
            let autoEnabled = handlePermissionReadiness(PermissionChecker.snapshot())
            if !autoEnabled, settings.listeningEnabled, !globalStopActive {
                startListening(showFailureHUD: true)
            }
            rebuildMenu()
        }
    }

    @objc private func requestAccessibilityPermission() {
        PermissionChecker.requestAccessibilityPrompt()
        let autoEnabled = handlePermissionReadiness(PermissionChecker.snapshot())
        if !autoEnabled, settings.listeningEnabled, !globalStopActive {
            startListening(showFailureHUD: true)
        }
        rebuildMenu()
        applyPendingConfigHotReloadIfNeeded()
    }

    @objc private func requestInputMonitoringPermission() {
        PermissionChecker.requestInputMonitoringPrompt()
        let autoEnabled = handlePermissionReadiness(PermissionChecker.snapshot())
        if !autoEnabled, settings.listeningEnabled, !globalStopActive {
            startListening(showFailureHUD: true)
        }
        rebuildMenu()
    }

    @objc private func openMicrophoneSettings() {
        PermissionChecker.openMicrophoneSettings()
    }

    @objc private func openAccessibilitySettings() {
        PermissionChecker.openAccessibilitySettings()
    }

    @objc private func openInputMonitoringSettings() {
        PermissionChecker.openInputMonitoringSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func restartApp() {
        let bundleURL = RestartAppPlanner.bundleURL(currentBundleURL: Bundle.main.bundleURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", bundleURL.path]
        do {
            try process.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                NSApp.terminate(nil)
            }
        } catch {
            hud.showWarningStatus(strings.restartFailed, duration: warningDuration)
            recordLocalDiagnostic(stage: "restart_failed", errorKind: diagnosticKind(for: error))
        }
    }

    private func runStartupPermissionGuideIfNeeded() async {
        await runPermissionGuide(isManualRequest: false)
    }

    private func runPermissionGuide(isManualRequest: Bool) async {
        let snapshot = PermissionChecker.snapshot()
        let currentIdentity = PermissionInstallIdentity.current()
        let runState = PermissionGuideRunState(
            didRunStartupGuide: settings.didRunStartupPermissionGuide,
            storedIdentity: settings.startupPermissionGuideIdentity,
            currentIdentity: currentIdentity
        )
        let actions = PermissionGuidePlanner.actions(
            for: snapshot,
            hasRunStartupGuide: runState.hasRunForCurrentIdentity,
            isManualRequest: isManualRequest
        )
        guard !actions.isEmpty else {
            let autoEnabled = handlePermissionReadiness(snapshot)
            if !autoEnabled, stopReason == .permissionBlocked {
                schedulePermissionReadinessPollingIfNeeded()
            }
            if autoEnabled || isManualRequest {
                rebuildMenu()
            }
            return
        }

        settings.didRunStartupPermissionGuide = true
        settings.startupPermissionGuideIdentity = currentIdentity
        if actions.contains(.requestMicrophone) {
            _ = await PermissionChecker.requestMicrophone()
        }
        if actions.contains(.requestAccessibility) {
            PermissionChecker.requestAccessibilityPrompt()
        }
        if actions.contains(.requestInputMonitoring) {
            PermissionChecker.requestInputMonitoringPrompt()
        }

        try? await Task.sleep(nanoseconds: 700_000_000)
        let updated = PermissionChecker.snapshot()
        if actions.contains(.openInputMonitoringSettings), !updated.inputMonitoringGranted {
            tapStatus = strings.listeningUnavailable()
            if isManualRequest {
                hud.showWarningStatus(strings.inputMonitoringManual, duration: warningDuration)
            }
            PermissionChecker.openInputMonitoringSettings()
        }
        let autoEnabled = handlePermissionReadiness(updated)
        if !autoEnabled, settings.listeningEnabled, !globalStopActive {
            startListening(showFailureHUD: isManualRequest)
        }
        rebuildMenu()
    }

    private func applyPersistedStoppedState() {
        globalStopActive = true
        switch stopReason {
        case .permissionBlocked:
            tapStatus = strings.listeningUnavailable()
            schedulePermissionReadinessPollingIfNeeded()
        case .previousRunRecovery:
            tapStatus = strings.stoppedAfterPreviousRun
        case .manual, nil:
            tapStatus = strings.stopped
        }
    }

    private func startListening(showFailureHUD: Bool = false) {
        guard !globalStopActive else {
            tapStatus = strings.stopped
            return
        }
        let snapshot = PermissionChecker.snapshot()
        lastPermissionSnapshot = snapshot
        let otherInstanceCount = otherRunningOmniVoiceApplications().count
        guard PermissionListeningStartupPlanner.shouldStartListening(
            listeningEnabled: settings.listeningEnabled,
            globalStopActive: globalStopActive,
            permissions: snapshot,
            hasOtherRunningInstance: otherInstanceCount > 0
        ) else {
            eventTap.setTriggerSuppressionEnabled(false)
            eventTap.stop()
            tapStatus = strings.listeningUnavailable()
            if otherInstanceCount > 0 {
                settings.listeningEnabled = false
                globalStopActive = true
                stopReason = .manual
                settings.stopReason = .manual
                tapStatus = strings.stopped
                recordLocalDiagnostic(
                    stage: "listening_start_blocked",
                    errorKind: "single_instance_conflict",
                    details: diagnosticRuntimeDetails(["other_instance_count": "\(otherInstanceCount)"])
                )
            } else if !snapshot.allRequiredGranted {
                enterPermissionBlockedStop()
            }
            if showFailureHUD {
                hud.showWarningStatus(strings.permissionIssue, duration: warningDuration)
            }
            rebuildMenu()
            return
        }
        eventTapFailureHUDEnabled = showFailureHUD
        eventTap.update(triggerKey: settings.triggerKey)
        eventTap.updateWatchdogTimeout(seconds: TimeInterval(settings.maxRecordingDuration.rawValue + 5))
        updateEventTapTriggerSuppression()
        let started = eventTap.start()
        tapStatus = started ? strings.listeningWithTrigger(settings.triggerKey) : strings.listeningUnavailable()
        if started {
            schedulePermissionDriftMonitoringIfNeeded()
        }
        if !started {
            if !snapshot.allRequiredGranted {
                enterPermissionBlockedStop()
            }
            if showFailureHUD {
                hud.showWarningStatus(strings.permissionIssue, duration: warningDuration)
            }
        }
    }

    private func normalizeHUDStyleAvailability() {
        let sanitized = HUDVisualStyleAvailability.sanitizedSelection(settings.hudVisualStyle)
        if sanitized != settings.hudVisualStyle {
            settings.hudVisualStyle = sanitized
        }
    }

    @discardableResult
    private func handlePermissionReadiness(_ snapshot: PermissionSnapshot) -> Bool {
        defer { lastPermissionSnapshot = snapshot }
        guard PermissionReadinessPlanner.shouldAutoEnable(
            previous: lastPermissionSnapshot,
            current: snapshot,
            stopReason: stopReason
        ) else {
            return false
        }
        globalStopActive = false
        stopReason = nil
        settings.stopReason = nil
        stopPermissionReadinessPolling()
        settings.listeningEnabled = true
        tapStatus = strings.listeningWithTrigger(settings.triggerKey)
        startListening(showFailureHUD: false)
        recordLocalDiagnostic(stage: "permissions_ready_auto_reenabled")
        return true
    }

    private func enterPermissionBlockedStop(recordDiagnostic: Bool = true) {
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil
        resetListeningHUDRevealState()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        recordingSource.cancel()
        eventTap.setCancellationActive(false)
        eventTap.setTriggerSuppressionEnabled(false)
        eventTap.stop()
        stopPermissionDriftMonitoring()
        state = .idle
        settings.listeningEnabled = false
        globalStopActive = true
        stopReason = .permissionBlocked
        settings.stopReason = .permissionBlocked
        tapStatus = strings.listeningUnavailable()
        schedulePermissionReadinessPollingIfNeeded()
        if recordDiagnostic {
            recordLocalDiagnostic(stage: "permission_blocked_stop", errorKind: "permissions_missing")
        }
    }

    private func schedulePermissionReadinessPollingIfNeeded() {
        guard stopReason == .permissionBlocked else { return }
        guard permissionReadinessTimer == nil else { return }
        permissionReadinessTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPermissionReadiness()
            }
        }
        permissionReadinessTimer?.tolerance = 0.3
    }

    private func stopPermissionReadinessPolling() {
        permissionReadinessTimer?.invalidate()
        permissionReadinessTimer = nil
    }

    private func schedulePermissionDriftMonitoringIfNeeded() {
        guard permissionDriftTimer == nil else { return }
        permissionDriftTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPermissionDrift()
            }
        }
        permissionDriftTimer?.tolerance = 0.4
    }

    private func stopPermissionDriftMonitoring() {
        permissionDriftTimer?.invalidate()
        permissionDriftTimer = nil
    }

    private func pollPermissionDrift() {
        guard settings.listeningEnabled, !globalStopActive else {
            stopPermissionDriftMonitoring()
            return
        }
        let current = PermissionChecker.snapshot()
        let shouldStop = PermissionDriftPlanner.shouldEnterPermissionBlockedStop(
            previous: lastPermissionSnapshot,
            current: current,
            listeningEnabled: settings.listeningEnabled,
            globalStopActive: globalStopActive
        )
        lastPermissionSnapshot = current
        guard shouldStop else { return }
        recordLocalDiagnostic(
            stage: "permission_drift_detected",
            errorKind: "permissions_missing",
            details: diagnosticRuntimeDetails(permissionDetails(current))
        )
        enterPermissionBlockedStop(recordDiagnostic: false)
        rebuildMenu()
    }

    private func pollPermissionReadiness() {
        guard stopReason == .permissionBlocked else {
            stopPermissionReadinessPolling()
            return
        }
        if handlePermissionReadiness(PermissionChecker.snapshot()) {
            rebuildMenu()
        }
    }

    private func handleEventTapSignal(_ signal: EventTapSignal) {
        switch signal {
        case .triggerDown:
            eventTap.acknowledgeMainSignal()
            recordLocalDiagnostic(
                stage: "trigger_down_received",
                details: [
                    "trigger": settings.triggerKey.identifier,
                    "state": String(describing: state),
                    "listening_enabled": settings.listeningEnabled ? "true" : "false"
                ]
            )
            beginRecording()
        case .triggerUp:
            eventTap.acknowledgeMainSignal()
            recordLocalDiagnostic(
                stage: "trigger_up_received",
                details: [
                    "trigger": settings.triggerKey.identifier,
                    "state": String(describing: state)
                ]
            )
            finishRecordingAndTranscribe()
        case .cancel(let reason):
            cancelCurrentOperation(reason: reason)
        case .tapDisabled:
            handleEventTapDisabled()
        case .tapReenabled:
            tapStatus = strings.listeningWithTrigger(settings.triggerKey)
            recordLocalDiagnostic(stage: "event_tap_reenabled")
            rebuildMenu()
        case .tapFailed:
            tapStatus = strings.listeningUnavailable()
            if eventTapFailureHUDEnabled {
                hud.showWarningStatus(strings.permissionIssue, duration: warningDuration)
            }
            recordLocalDiagnostic(stage: "event_tap_failed", errorKind: "tap_failed")
            rebuildMenu()
        case .triggerAckTimeout:
            handleTriggerAckTimeout()
        case .triggerWatchdogReset:
            tapStatus = strings.eventTapWatchdogReset
            hud.showTransientStatus(strings.eventTapWatchdogReset, duration: warningDuration)
            recordLocalDiagnostic(
                stage: "event_tap_watchdog_reset",
                errorKind: "trigger_state_stale",
                details: ["trigger": settings.triggerKey.identifier]
            )
            rebuildMenu()
        case .emergencyRescue:
            performEmergencyRescueExit()
        }
    }

    private func handleEventTapDisabled() {
        eventTap.stop()
        tapStatus = strings.eventTapDisabled()
        let snapshot = PermissionChecker.snapshot()
        lastPermissionSnapshot = snapshot
        recordLocalDiagnostic(
            stage: "event_tap_disabled",
            errorKind: "tap_disabled",
            details: diagnosticRuntimeDetails(permissionDetails(snapshot))
        )
        switch EventTapDisabledRecoveryPlanner.action(
            listeningEnabled: settings.listeningEnabled,
            globalStopActive: globalStopActive,
            permissions: snapshot
        ) {
        case .enterPermissionBlockedStop:
            enterPermissionBlockedStop(recordDiagnostic: false)
        case .restartListening:
            startListening(showFailureHUD: false)
        case .stayStopped:
            break
        }
        rebuildMenu()
    }

    private func handleTriggerAckTimeout() {
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil
        resetListeningHUDRevealState()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        recordingSource.cancel()
        eventTap.setCancellationActive(false)
        eventTap.setTriggerSuppressionEnabled(false)
        eventTap.stop()
        hud.hide()
        actionPanel.cancel()
        recordingFocus = nil
        recordingStartDate = nil
        pendingTranscription = nil
        stopPermissionDriftMonitoring()
        state = .idle
        settings.listeningEnabled = false
        globalStopActive = true
        stopReason = .manual
        settings.stopReason = .manual
        tapStatus = strings.stopped
        recordLocalDiagnostic(
            stage: "event_tap_trigger_ack_timeout",
            errorKind: "trigger_ack_timeout",
            details: diagnosticRuntimeDetails(["listening_enabled": "false"])
        )
        rebuildMenu()
    }

    private func performEmergencyRescueExit() {
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil
        resetListeningHUDRevealState()
        transcriptionTask?.cancel()
        transcriptionTask = nil
        recordingSource.cancel()
        triggerCapture.stop()
        eventTap.setCancellationActive(false)
        eventTap.setTriggerSuppressionEnabled(false)
        eventTap.stop()
        hud.hide()
        actionPanel.cancel()
        recordingFocus = nil
        recordingStartDate = nil
        pendingTranscription = nil
        stopPermissionReadinessPolling()
        stopPermissionDriftMonitoring()
        state = .idle
        settings.listeningEnabled = false
        globalStopActive = true
        stopReason = .manual
        settings.stopReason = .manual
        settings.runtimeActive = false
        tapStatus = strings.stopped
        recordLocalDiagnostic(
            stage: "fn_escape_quit",
            errorKind: "emergency_rescue",
            details: diagnosticRuntimeDetails(["listening_enabled": "false"])
        )
        NSApp.terminate(nil)
    }

    func runRecordingReplayForAutomation(
        options: RecordingReplayAutomationOptions
    ) async -> RecordingReplayAutomationResult {
        guard automationContinuation == nil else {
            return RecordingReplayAutomationResult(
                ok: false,
                recordingSeconds: nil,
                wavBytes: nil,
                overallRMS: nil,
                originalBundleIdentifier: recordingFocus?.bundleIdentifier,
                originalAppName: recordingFocus?.appName,
                originalFocusFailure: recordingFocus?.failureReason.rawValue,
                injectionResult: nil,
                fallbackReason: nil,
                errorKind: "automation_already_running"
            )
        }

        return await withCheckedContinuation { continuation in
            automationOptions = options
            automationRecordingResult = nil
            automationContinuation = continuation
            if let uiLanguage = options.uiLanguage {
                automationPreviousUILanguage = settings.uiLanguage
                settings.uiLanguage = uiLanguage
            }
            let visualStyle = options.hudVisualStyle ?? settings.hudVisualStyle
            hud.setVisualStyle(visualStyle)
            actionPanel.setVisualStyle(visualStyle)
            beginRecording()
            startAutomationGUIFrameCaptureIfNeeded()

            guard automationContinuation != nil else { return }
            let replaySource = recordingSource as? any ReplayRecordingSource
            Task { @MainActor [weak self] in
                if let replaySource {
                    await replaySource.waitUntilReplayFinished()
                } else {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                guard let self, self.automationContinuation != nil else { return }
                self.finishRecordingAndTranscribe()
            }
        }
    }

    private func completeAutomation(
        ok: Bool,
        pending: PendingTranscription?,
        injectionResult: String?,
        fallbackReason: String?,
        errorKind: String?
    ) {
        guard let continuation = automationContinuation else { return }
        stopAutomationGUIFrameCapture()
        let recording = pending?.result ?? automationRecordingResult
        let focus = pending?.originalFocus ?? recordingFocus
        if let previous = automationPreviousUILanguage {
            settings.uiLanguage = previous
        }
        automationContinuation = nil
        automationOptions = nil
        automationRecordingResult = nil
        automationPreviousUILanguage = nil
        continuation.resume(returning: RecordingReplayAutomationResult(
            ok: ok,
            recordingSeconds: recording?.durationSeconds,
            wavBytes: recording?.wavData.count,
            overallRMS: recording?.overallRMS,
            originalBundleIdentifier: focus?.bundleIdentifier,
            originalAppName: focus?.appName,
            originalFocusFailure: focus?.failureReason.rawValue,
            injectionResult: injectionResult,
            fallbackReason: fallbackReason,
            errorKind: errorKind
        ))
    }

    private func startAutomationGUIFrameCaptureIfNeeded() {
        guard let options = automationOptions,
              options.recordGUIFrames,
              automationGUIFrameTimer == nil else { return }
        automationGUIFrameIndex = 0
        recordAutomationGUIFrame(stage: "gui_frame_start")
        let interval = max(1.0 / 30.0, min(options.guiFrameIntervalSeconds, 1.0))
        automationGUIFrameTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordAutomationGUIFrame(stage: "gui_frame")
            }
        }
    }

    private func stopAutomationGUIFrameCapture() {
        guard automationGUIFrameTimer != nil || automationGUIFrameIndex > 0 else { return }
        recordAutomationGUIFrame(stage: "gui_frame_final")
        automationGUIFrameTimer?.invalidate()
        automationGUIFrameTimer = nil
    }

    private func recordAutomationGUIFrame(stage: String) {
        guard automationOptions?.recordGUIFrames == true else { return }
        let actionPanelSnapshot = actionPanel.diagnosticSnapshot
        let hudSnapshot = hud.diagnosticSnapshot
        let snapshot: SurfaceDiagnosticSnapshot
        let screenshotPNGData: Data?
        if actionPanelSnapshot.isVisible {
            snapshot = actionPanelSnapshot
            screenshotPNGData = actionPanel.renderedPNGData()
        } else if hudSnapshot.isVisible {
            snapshot = hudSnapshot
            screenshotPNGData = hud.renderedPNGData()
        } else {
            return
        }
        guard screenshotPNGData != nil else { return }
        automationGUIFrameIndex += 1
        var details = [
            "frame_index": "\(automationGUIFrameIndex)",
            "panel_type": snapshot.panelType,
            "level": snapshot.levelName,
            "is_visible": snapshot.isVisible ? "true" : "false"
        ]
        if let frame = snapshot.frame {
            details["x"] = String(format: "%.1f", frame.origin.x)
            details["y"] = String(format: "%.1f", frame.origin.y)
            details["width"] = String(format: "%.1f", frame.width)
            details["height"] = String(format: "%.1f", frame.height)
        }
        if let windowNumber = snapshot.windowNumber {
            details["window_number"] = "\(windowNumber)"
        }
        automationEventSink?.record(AutomationEvent(
            stage: stage,
            details: details,
            surface: snapshot,
            screenshotPNGData: screenshotPNGData
        ))
    }

    private func scheduleListeningHUDReveal() {
        cancelListeningHUDRevealTimer()
        listeningHUDShownForCurrentRecording = false
        listeningHUDRevealTimer = Timer.scheduledTimer(
            withTimeInterval: settings.hudRevealDelay.seconds,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.revealListeningHUDIfNeeded()
            }
        }
    }

    private func revealListeningHUDIfNeeded() {
        listeningHUDRevealTimer?.invalidate()
        listeningHUDRevealTimer = nil
        guard ListeningHUDRevealPlanner.shouldReveal(
            isRecording: state == .recording,
            cancelled: false
        ) else {
            return
        }
        listeningHUDShownForCurrentRecording = true
        hud.showListening(text: strings.listening)
        recordHUDDiagnostic(stage: "hud_show_listening")
    }

    private func cancelListeningHUDRevealTimer() {
        listeningHUDRevealTimer?.invalidate()
        listeningHUDRevealTimer = nil
    }

    private func resetListeningHUDRevealState() {
        cancelListeningHUDRevealTimer()
        listeningHUDShownForCurrentRecording = false
    }

    private func beginRecording() {
        let isAutomation = automationContinuation != nil
        guard isAutomation || (settings.listeningEnabled && !globalStopActive && state == .idle) else {
            recordLocalDiagnostic(
                stage: "recording_start_ignored",
                errorKind: "state_not_ready",
                details: [
                    "state": String(describing: state),
                    "listening_enabled": settings.listeningEnabled ? "true" : "false",
                    "stopped": globalStopActive ? "true" : "false"
                ]
            )
            completeAutomation(
                ok: false,
                pending: nil,
                injectionResult: nil,
                fallbackReason: nil,
                errorKind: "recording_start_ignored"
            )
            return
        }
        guard state == .idle else {
            completeAutomation(
                ok: false,
                pending: nil,
                injectionResult: nil,
                fallbackReason: nil,
                errorKind: "state_not_idle"
            )
            return
        }
        recordingFocus = textInjector.captureFocusSnapshot(
            targetBundleIdentifier: automationOptions?.targetBundleIdentifier
        )
        recordingStartDate = Date()
        state = .recording
        eventTap.setCancellationActive(true)
        updateEventTapTriggerSuppression()
        actionPanel.cancel()
        rebuildMenu()
        recordLocalDiagnostic(
            stage: "recording_start_requested",
            details: [
                "trigger": settings.triggerKey.identifier,
                "min_duration_seconds": String(format: "%.3f", settings.minRecordingDuration.seconds),
                "max_duration_seconds": "\(settings.maxRecordingDuration.rawValue)"
            ]
        )
        do {
            try recordingSource.start()
            recordLocalDiagnostic(stage: "recording_started", details: ["trigger": settings.triggerKey.identifier])
            scheduleListeningHUDReveal()
            maxRecordingTimer?.invalidate()
            maxRecordingTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.maxRecordingDuration.rawValue), repeats: false) { [weak self] _ in
                Task { @MainActor in self?.finishRecordingAndTranscribe() }
            }
            rebuildMenu()
        } catch {
            state = .idle
            recordingStartDate = nil
            recordingFocus = nil
            resetListeningHUDRevealState()
            eventTap.setCancellationActive(false)
            updateEventTapTriggerSuppression()
            recordLocalDiagnostic(
                stage: "recording_start_failed",
                errorKind: diagnosticKind(for: error)
            )
            hud.showWarningStatus(sanitizedMessage(for: error), duration: warningDuration)
            rebuildMenu()
            completeAutomation(
                ok: false,
                pending: nil,
                injectionResult: nil,
                fallbackReason: nil,
                errorKind: diagnosticKind(for: error)
            )
        }
    }

    private func finishRecordingAndTranscribe() {
        guard state == .recording else {
            recordLocalDiagnostic(
                stage: "recording_stop_ignored",
                errorKind: "state_not_recording",
                details: ["state": String(describing: state)]
            )
            return
        }
        let elapsed = recordingStartDate.map { Date().timeIntervalSince($0) }
        recordLocalDiagnostic(
            stage: "recording_stop_requested",
            details: elapsed.map { ["elapsed_seconds": String(format: "%.3f", $0)] } ?? [:]
        )
        let listeningHUDWasShown = listeningHUDShownForCurrentRecording
        cancelListeningHUDRevealTimer()
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil

        let result: AudioRecordingResult
        do {
            result = try recordingSource.stop(minimumDurationSeconds: settings.minRecordingDuration.seconds)
            automationRecordingResult = result
            recordingStartDate = nil
            listeningHUDShownForCurrentRecording = false
            recordLocalDiagnostic(
                stage: "recording_stopped",
                details: [
                    "recording_seconds": String(format: "%.3f", result.durationSeconds),
                    "rms": String(format: "%.5f", result.overallRMS),
                    "wav_bytes": "\(result.wavData.count)"
                ]
            )
        } catch {
            state = .idle
            recordingStartDate = nil
            listeningHUDShownForCurrentRecording = false
            eventTap.setCancellationActive(false)
            updateEventTapTriggerSuppression()
            let message = sanitizedMessage(for: error)
            let validationStatus = recordingValidationStatus(for: error)
            let shouldShowHUD = RecordingStopFailurePresentationPlanner.shouldShowHUD(
                validationStatus: validationStatus,
                listeningHUDWasShown: listeningHUDWasShown
            )
            recordLocalDiagnostic(
                stage: "recording_stop_failed",
                errorKind: diagnosticKind(for: error),
                details: {
                    var details = elapsed.map { ["elapsed_seconds": String(format: "%.3f", $0)] } ?? [:]
                    details["hud_visible_before_stop"] = listeningHUDWasShown ? "true" : "false"
                    details["shown_to_user"] = shouldShowHUD ? "true" : "false"
                    return details
                }()
            )
            if shouldShowHUD {
                hud.showWarningStatus(message, duration: warningDuration)
            } else {
                hud.hide()
            }
            rebuildMenu()
            completeAutomation(
                ok: false,
                pending: nil,
                injectionResult: nil,
                fallbackReason: nil,
                errorKind: diagnosticKind(for: error)
            )
            return
        }

        let model = automationOptions?.model ?? settings.selectedModel
        let styleDescriptor = automationOptions?.styleSelection.map {
            TranscriptionStyleResolver.resolve(selection: $0, customStyles: config.customStyles)
        } ?? currentStyleDescriptor
        let instruction = TranscriptionInstructionBuilder.instruction(
            descriptor: styleDescriptor,
            keywordHints: currentKeywordHintsContext
        )
        let shouldAutoInsert: Bool
        let autoInsertSkipReason: String?
        if automationOptions?.forceActionPanel == true {
            shouldAutoInsert = false
            autoInsertSkipReason = "forced_action_panel"
        } else if automationOptions?.forceAutoInsert == true {
            shouldAutoInsert = true
            autoInsertSkipReason = nil
        } else {
            autoInsertSkipReason = settings.autoInsert && globalStopActive ? "global_stop_auto_insert_disabled" : nil
            shouldAutoInsert = settings.autoInsert && !globalStopActive
        }
        let focus = recordingFocus
        let pending = PendingTranscription(
            result: result,
            model: model,
            instruction: instruction,
            styleSelection: styleDescriptor.selection,
            shouldAutoInsert: shouldAutoInsert,
            autoInsertSkipReason: autoInsertSkipReason,
            originalFocus: focus,
            fallbackResult: nil
        )
        pendingTranscription = pending
        startTranscription(pending)
    }

    private func startTranscription(_ pending: PendingTranscription) {
        resetListeningHUDRevealState()
        state = .transcribing
        eventTap.setCancellationActive(true)
        updateEventTapTriggerSuppression()
        hud.showTranscribing(recordingSeconds: pending.result.durationSeconds, text: strings.transcribing)
        recordHUDDiagnostic(stage: "hud_show_transcribing")
        rebuildMenu()
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let finalText = try await client.transcribe(
                    wavData: pending.result.wavData,
                    model: pending.model,
                    instruction: pending.instruction,
                    recordingSeconds: pending.result.durationSeconds,
                    overallRMS: pending.result.overallRMS,
                    allowEmptyFinalText: false,
                    onDelta: { [weak self] delta in
                        DispatchQueue.main.async {
                            self?.hud.appendTranscriptionDelta(delta)
                        }
                    }
                )
                if Task.isCancelled { return }
                await self.finishTranscription(
                    finalText: finalText,
                    pending: pending
                )
            } catch {
                await self.failTranscription(error, pending: pending)
            }
        }
    }

    private func finishTranscription(
        finalText: String,
        pending: PendingTranscription
    ) async {
        state = .idle
        eventTap.setCancellationActive(false)
        updateEventTapTriggerSuppression()
        transcriptionTask = nil

        guard !finalText.isEmpty else {
            hud.showWarningStatus(strings.noTextRecognized, duration: warningDuration)
            rebuildMenu()
            applyPendingConfigHotReloadIfNeeded()
            completeAutomation(
                ok: false,
                pending: pending,
                injectionResult: nil,
                fallbackReason: nil,
                errorKind: "empty_final_text"
            )
            return
        }

        if pending.shouldAutoInsert {
            let result = await textInjector.insertFinalText(
                finalText,
                originalFocus: pending.originalFocus,
                targetBundleIdentifier: automationOptions?.targetBundleIdentifier
            )
            switch result {
            case .inserted:
                updateLastDiagnosticInsertion(nil)
                pendingTranscription = nil
                recordingFocus = nil
                hud.completeAndHide()
                completeAutomation(
                    ok: true,
                    pending: pending,
                    injectionResult: "inserted",
                    fallbackReason: nil,
                    errorKind: nil
                )
            case .fallback(let reason):
                updateLastDiagnosticInsertion(reason.rawValue)
                showResultActionPanel(text: finalText, pending: pending)
                completeAutomation(
                    ok: false,
                    pending: pending,
                    injectionResult: "fallback",
                    fallbackReason: reason.rawValue,
                    errorKind: reason.rawValue
                )
            }
        } else {
            if let autoInsertSkipReason = pending.autoInsertSkipReason {
                recordLocalDiagnostic(
                    stage: "injection_skipped",
                    errorKind: autoInsertSkipReason,
                    details: ["text_chars": "\(finalText.count)"]
                )
            }
            showResultActionPanel(text: finalText, pending: pending)
            if automationOptions?.forceActionPanel == true {
                try? await Task.sleep(nanoseconds: 550_000_000)
                recordActionPanelDiagnostic(stage: "action_panel_stable_result")
            }
            completeAutomation(
                ok: automationOptions?.forceActionPanel == true,
                pending: pending,
                injectionResult: automationOptions?.forceActionPanel == true ? "action_panel" : "fallback",
                fallbackReason: pending.autoInsertSkipReason ?? "auto_insert_disabled",
                errorKind: pending.autoInsertSkipReason ?? "auto_insert_disabled"
            )
        }
        rebuildMenu()
        applyPendingConfigHotReloadIfNeeded()
    }

    private func updateLastDiagnosticInsertion(_ reason: String?) {
        let diagnostic = RuntimeDiagnostic(
            stage: "injection_complete",
            host: "local",
            insertionFallbackReason: reason,
            errorKind: reason,
            details: ["result": reason == nil ? "inserted" : "fallback"]
        )
        RuntimeDiagnostic.log(diagnostic)
        recordDiagnostic(diagnostic)
    }

    private func recordDiagnostic(_ diagnostic: RuntimeDiagnostic) {
        lastDiagnostic = diagnostic
        rebuildMenu()
    }

    private func recordLocalDiagnostic(
        stage: String,
        errorKind: String? = nil,
        details: [String: String] = [:]
    ) {
        let diagnostic = RuntimeDiagnostic(
            stage: stage,
            host: "local",
            errorKind: errorKind,
            details: details
        )
        RuntimeDiagnostic.log(diagnostic)
        recordDiagnostic(diagnostic)
        automationEventSink?.record(AutomationEvent(
            stage: stage,
            errorKind: errorKind,
            details: details
        ))
    }

    private func recordHUDDiagnostic(stage: String) {
        recordSurfaceDiagnostic(
            stage: stage,
            snapshot: hud.diagnosticSnapshot,
            screenshotPNGData: hud.renderedPNGData()
        )
    }

    private func recordActionPanelDiagnostic(stage: String) {
        recordSurfaceDiagnostic(
            stage: stage,
            snapshot: actionPanel.diagnosticSnapshot,
            screenshotPNGData: actionPanel.renderedPNGData()
        )
    }

    private func recordSurfaceDiagnostic(
        stage: String,
        snapshot: SurfaceDiagnosticSnapshot,
        screenshotPNGData: Data?
    ) {
        guard let frame = snapshot.frame else {
            recordLocalDiagnostic(
                stage: stage,
                errorKind: "\(snapshot.panelType)_not_visible",
                details: [
                    "panel_type": snapshot.panelType,
                    "level": snapshot.levelName,
                    "is_visible": snapshot.isVisible ? "true" : "false"
                ]
            )
            automationEventSink?.record(AutomationEvent(
                stage: stage,
                errorKind: "\(snapshot.panelType)_not_visible",
                details: [
                    "panel_type": snapshot.panelType,
                    "level": snapshot.levelName,
                    "is_visible": snapshot.isVisible ? "true" : "false"
                ],
                surface: snapshot,
                screenshotPNGData: nil
            ))
            return
        }
        var details = [
            "panel_type": snapshot.panelType,
            "level": snapshot.levelName,
            "is_visible": snapshot.isVisible ? "true" : "false",
            "x": String(format: "%.1f", frame.origin.x),
            "y": String(format: "%.1f", frame.origin.y),
            "width": String(format: "%.1f", frame.width),
            "height": String(format: "%.1f", frame.height)
        ]
        if let windowNumber = snapshot.windowNumber {
            details["window_number"] = "\(windowNumber)"
        }
        recordLocalDiagnostic(stage: stage, details: details)
        automationEventSink?.record(AutomationEvent(
            stage: stage,
            details: details,
            surface: snapshot,
            screenshotPNGData: screenshotPNGData
        ))
    }

    private func failTranscription(_ error: Error, pending: PendingTranscription?) async {
        state = .idle
        eventTap.setCancellationActive(false)
        updateEventTapTriggerSuppression()
        transcriptionTask = nil
        if Task.isCancelled {
            hud.showTransientStatus(strings.cancelled, duration: warningDuration)
            pendingTranscription = nil
            recordingFocus = nil
            completeAutomation(
                ok: false,
                pending: pending,
                injectionResult: nil,
                fallbackReason: nil,
                errorKind: "cancelled"
            )
        } else {
            showRetryActionPanel(error: error, pending: pending)
            completeAutomation(
                ok: false,
                pending: pending,
                injectionResult: nil,
                fallbackReason: nil,
                errorKind: diagnosticKind(for: error)
            )
        }
        rebuildMenu()
        applyPendingConfigHotReloadIfNeeded()
    }

    private func showRetryActionPanel(error: Error, pending: PendingTranscription?) {
        let message = sanitizedMessage(for: error)
        let startFrame = hud.frameForMorphAndHide()
        actionPanel.showRetry(
            title: strings.requestFailed,
            message: message,
            retryTitle: strings.retry,
            cancelTitle: strings.cancel,
            from: startFrame,
            onRetry: { [weak self] in
                guard let self else { return }
                if let pending {
                    self.startTranscription(pending)
                }
            },
            onCancel: { [weak self] in
                guard let self else { return }
                if let pending, let fallback = pending.fallbackResult {
                    let restored = PendingTranscription(
                        result: pending.result,
                        model: pending.model,
                        instruction: fallback.instruction,
                        styleSelection: fallback.styleSelection,
                        shouldAutoInsert: false,
                        autoInsertSkipReason: nil,
                        originalFocus: pending.originalFocus,
                        fallbackResult: nil
                    )
                    self.pendingTranscription = restored
                    self.showResultActionPanel(text: fallback.text, pending: restored)
                } else {
                    self.pendingTranscription = nil
                    self.recordingFocus = nil
                }
            }
        )
        recordActionPanelDiagnostic(stage: "action_panel_show_retry")
    }

    private func showResultActionPanel(text: String, pending: PendingTranscription) {
        let startFrame = hud.frameForMorphAndHide()
        let descriptor = TranscriptionStyleResolver.resolve(
            selection: pending.styleSelection,
            customStyles: config.customStyles
        )
        actionPanel.showResult(
            text: text,
            copyTitle: strings.copy,
            styleTitle: strings.panelStyleSwitchTitle(descriptor),
            styleOptions: actionPanelStyleOptions(),
            selectedStyle: descriptor.selection,
            cancelTitle: strings.cancel,
            copiedTitle: strings.copied,
            from: startFrame,
            onCopy: { [weak self] in
                self?.pendingTranscription = nil
                self?.recordingFocus = nil
            },
            onStyleSelected: { [weak self] selection in
                guard let self else { return }
                self.switchResultStyle(selection, previousText: text, previousPending: pending)
            },
            onCancel: { [weak self] in
                self?.pendingTranscription = nil
                self?.recordingFocus = nil
            }
        )
        recordActionPanelDiagnostic(stage: "action_panel_show_result")
    }

    private func actionPanelStyleOptions() -> [ActionPanelStyleOption] {
        TranscriptionStyleResolver.menuDescriptors(customStyles: config.customStyles).map { descriptor in
            ActionPanelStyleOption(
                selection: descriptor.selection,
                title: strings.styleMenuItem(descriptor),
                tooltip: tooltip(for: descriptor)
            )
        }
    }

    private func switchResultStyle(
        _ selection: TranscriptionStyleSelection,
        previousText: String,
        previousPending: PendingTranscription
    ) {
        let descriptor = TranscriptionStyleResolver.resolve(
            selection: selection,
            customStyles: config.customStyles
        )
        let instruction = TranscriptionInstructionBuilder.instruction(
            descriptor: descriptor,
            keywordHints: currentKeywordHintsContext
        )
        let pending = PendingTranscription(
            result: previousPending.result,
            model: previousPending.model,
            instruction: instruction,
            styleSelection: descriptor.selection,
            shouldAutoInsert: false,
            autoInsertSkipReason: "panel_style_switch",
            originalFocus: previousPending.originalFocus,
            fallbackResult: PreviousPanelResult(
                text: previousText,
                instruction: previousPending.instruction,
                styleSelection: previousPending.styleSelection
            )
        )
        pendingTranscription = pending
        recordLocalDiagnostic(
            stage: "panel_style_switch",
            details: ["style": descriptor.selection.rawValue]
        )
        startTranscription(pending)
    }

    private func cancelCurrentOperation(reason: EventTapCancellationReason = .escapeKey) {
        switch state {
        case .recording:
            let isSilent = reason == .triggerCombination
            recordingSource.cancel()
            state = .idle
            eventTap.setCancellationActive(false)
            updateEventTapTriggerSuppression()
            maxRecordingTimer?.invalidate()
            maxRecordingTimer = nil
            resetListeningHUDRevealState()
            recordingFocus = nil
            recordingStartDate = nil
            pendingTranscription = nil
            actionPanel.cancel()
            if isSilent {
                hud.hide()
            } else {
                hud.showTransientStatus(strings.cancelled, duration: warningDuration)
            }
            recordLocalDiagnostic(
                stage: "recording_cancelled",
                errorKind: isSilent ? "trigger_combination_cancelled" : "cancelled",
                details: [
                    "reason": String(describing: reason),
                    "shown_to_user": isSilent ? "false" : "true"
                ]
            )
            completeAutomation(
                ok: false,
                pending: nil,
                injectionResult: nil,
                fallbackReason: nil,
                errorKind: isSilent ? "trigger_combination_cancelled" : "cancelled"
            )
        case .transcribing:
            let pending = pendingTranscription
            transcriptionTask?.cancel()
            transcriptionTask = nil
            state = .idle
            eventTap.setCancellationActive(false)
            updateEventTapTriggerSuppression()
            recordingFocus = nil
            resetListeningHUDRevealState()
            pendingTranscription = nil
            actionPanel.cancel()
            hud.showTransientStatus(strings.cancelled, duration: warningDuration)
            completeAutomation(
                ok: false,
                pending: pending,
                injectionResult: nil,
                fallbackReason: nil,
                errorKind: "cancelled"
            )
        case .idle:
            actionPanel.cancel()
            break
        }
        rebuildMenu()
        applyPendingConfigHotReloadIfNeeded()
    }

    private func refreshModels(showStatus: Bool) async {
        do {
            let ids = try await client.fetchModels()
            let filtered = AllowedSpeechModel.filterSpeechModels(from: ids)
            availableModels = filtered.isEmpty ? AllowedSpeechModel.allCases : filtered
            if showStatus {
                hud.showTransientStatus(strings.modelsRefreshed, duration: warningDuration)
            }
        } catch {
            if showStatus {
                hud.showWarningStatus(sanitizedMessage(for: error), duration: warningDuration)
            }
        }
        rebuildMenu()
    }

    private func sanitizedMessage(for error: Error) -> String {
        let description = (error as? LocalizedError)?.errorDescription ?? "操作失败"
        if description.count > 90 {
            return String(description.prefix(90)) + "…"
        }
        return description
    }

    private func diagnosticKind(for error: Error) -> String {
        if let audioError = error as? AudioRecorderError {
            return String(describing: audioError)
        }
        if let mimoError = error as? MimoAPIError {
            return mimoError.diagnosticKind
        }
        return String(describing: type(of: error))
    }

    private func recordingValidationStatus(for error: Error) -> RecordingValidationResult.Status? {
        guard let audioError = error as? AudioRecorderError else { return nil }
        switch audioError {
        case .tooShort:
            return .tooShort
        case .tooQuiet:
            return .tooQuiet
        case .alreadyRecording, .notRecording, .noInputFormat, .noSamples, .conversionFailed, .invalidWAV:
            return nil
        }
    }
}

private final class TriggerCaptureMenuView: NSView {
    private let button: NSButton
    private let hintLabel: NSTextField
    private let idleTitle: String
    private let idleHint: String
    private let captureTitle: String
    private let cancelHint: String
    private let onBegin: (TriggerCaptureMenuView) -> Void

    init(
        strings: UIStrings,
        selectedTriggerLabel: String,
        onBegin: @escaping (TriggerCaptureMenuView) -> Void
    ) {
        self.idleTitle = strings.recordTriggerKey
        self.idleHint = strings.language == .chinese ? "当前：\(selectedTriggerLabel)" : "Current: \(selectedTriggerLabel)"
        self.captureTitle = strings.recordingTriggerKey
        self.cancelHint = strings.language == .chinese ? "Esc 取消" : "Esc cancels"
        self.onBegin = onBegin
        self.button = NSButton(title: strings.recordTriggerKey, target: nil, action: nil)
        self.hintLabel = NSTextField(labelWithString: strings.triggerRecordingHelp)
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 38))
        toolTip = strings.tooltip(.triggerCapture)

        button.target = self
        button.action = #selector(beginPressed)
        button.bezelStyle = .rounded
        button.font = .menuFont(ofSize: 0)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.toolTip = strings.tooltip(.triggerCapture)

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.maximumNumberOfLines = 1
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(button)
        addSubview(hintLabel)
        endCapture()

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuLayoutMetrics.customViewLeading),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 118),

            hintLabel.leadingAnchor.constraint(equalTo: button.trailingAnchor, constant: 10),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            hintLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginCapture() {
        button.title = captureTitle
        hintLabel.stringValue = cancelHint
        hintLabel.textColor = .secondaryLabelColor
    }

    func endCapture() {
        button.title = idleTitle
        hintLabel.stringValue = idleHint
        hintLabel.textColor = .secondaryLabelColor
    }

    func showRejected(_ message: String) {
        hintLabel.stringValue = message
        hintLabel.textColor = NSColor(calibratedRed: 0.78, green: 0.25, blue: 0.22, alpha: 1.0)
    }

    func showSelected(_ triggerLabel: String) {
        button.title = idleTitle
        hintLabel.stringValue = triggerLabel
        hintLabel.textColor = NSColor(calibratedRed: 0.23, green: 0.58, blue: 0.35, alpha: 1.0)
    }

    @objc private func beginPressed() {
        onBegin(self)
    }
}
