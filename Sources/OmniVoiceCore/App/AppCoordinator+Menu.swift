import AppKit
import Foundation

extension AppCoordinator {
    func menuWillOpen(_ menu: NSMenu) {
        handlePermissionReadiness(PermissionChecker.snapshot())
        rebuildMenu()
    }

    func rebuildMenu() {
        statusItem.menu = MenuBuilder(coordinator: self).build()
    }

    var statusTitle: String {
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

    var connectionCheckTitle: String {
        if isTestingConnection {
            return strings.connectionCheckRunning()
        }
        if let lastTestConnectionResult {
            return strings.connectionCheckMessage(lastTestConnectionResult)
        }
        return strings.connectionCheckDefault()
    }

    func modelConfigurationMenu() -> NSMenu {
        let menu = NSMenu(title: strings.modelConfiguration)
        for mode in TranscriptionPipelineMode.allCases {
            let menuItem = item(title: mode.displayName(in: settings.uiLanguage), action: #selector(selectPipelineMode(_:)))
            menuItem.representedObject = mode.rawValue
            menuItem.state = mode == settings.pipelineMode ? .on : .off
            menuItem.toolTip = strings.tooltip(.transcriptionMode)
            menu.addItem(menuItem)
        }
        menu.addItem(NSMenuItem.separator())
        let availableModels = modelAvailabilityIndex.availableModels(for: settings.pipelineMode)
        if availableModels.isEmpty {
            menu.addItem(disabledItem(settings.pipelineMode == .systemASROnly ? strings.noLLMUsedForMode : strings.noObservedModels))
        } else {
            for model in availableModels {
                let menuItem = item(
                    title: model.rawValue,
                    action: #selector(selectPipelineModel(_:)),
                    tooltip: settings.pipelineMode == .inputAudio ? strings.tooltip(.inputAudioModel) : strings.tooltip(.textLLMModel)
                )
                menuItem.representedObject = model.rawValue
                menuItem.state = model == currentPipelineModel ? .on : .off
                menu.addItem(menuItem)
            }
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(title: strings.editModelList, action: #selector(openModelListConfigFile), tooltip: strings.tooltip(.editModelList)))
        return menu
    }

    func systemASRMenu() -> NSMenu {
        let menu = NSMenu(title: strings.systemASR)
        menu.addItem(submenuItem(
            strings.systemASREngineTitle(effectiveSystemASREngine),
            submenu: systemASREngineMenu(),
            tooltip: strings.tooltip(.systemASREngine)
        ))
        let keywordHints = item(
            title: strings.systemASRKeywordHints,
            action: #selector(toggleSystemASRKeywordHints),
            tooltip: strings.tooltip(.systemASRKeywordHints)
        )
        keywordHints.state = settings.systemASRKeywordHintsEnabled ? .on : .off
        menu.addItem(keywordHints)
        return menu
    }

    func systemASREngineMenu() -> NSMenu {
        let menu = NSMenu(title: strings.systemASREngine)
        for engine in SystemASREngine.allCases {
            let menuItem = item(
                title: engine.displayName(in: settings.uiLanguage),
                action: #selector(selectSystemASREngine(_:)),
                tooltip: strings.systemASREngineTooltip(engine)
            )
            menuItem.representedObject = engine.rawValue
            menuItem.state = engine == effectiveSystemASREngine ? .on : .off
            if engine == .speechAnalyzer && !speechAnalyzerAvailable {
                menuItem.isEnabled = false
            }
            menu.addItem(menuItem)
        }
        return menu
    }

    func languageMenu() -> NSMenu {
        let menu = NSMenu(title: strings.uiLanguageTitle(settings.uiLanguage))
        for language in UILanguage.allCases {
            let menuItem = item(title: language.displayName, action: #selector(selectLanguage(_:)))
            menuItem.representedObject = language.rawValue
            menuItem.state = language == settings.uiLanguage ? .on : .off
            menu.addItem(menuItem)
        }
        return menu
    }

    func styleMenu() -> NSMenu {
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
            action: #selector(openCustomStylesConfigFile),
            tooltip: strings.tooltip(.customStyles)
        ))
        return menu
    }

    func keywordHintsMenu() -> NSMenu {
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
                menu.addItem(menuItem)
            }
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(
            title: strings.editKeywords,
            action: #selector(openKeywordConfigFile),
            tooltip: strings.tooltip(.keywordHints)
        ))
        return menu
    }

    func triggerMenu() -> NSMenu {
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
        menu.addItem(NSMenuItem.separator())
        let continuousItem = item(
            title: strings.continuousRecordingDoubleTap,
            action: #selector(toggleContinuousRecordingDoubleTap),
            tooltip: continuousRecordingDoubleTapSupported
                ? strings.tooltip(.continuousRecordingDoubleTap)
                : strings.continuousRecordingUnsupportedForTrigger(settings.triggerKey)
        )
        continuousItem.state = settings.continuousRecordingDoubleTapEnabled ? .on : .off
        continuousItem.isEnabled = continuousRecordingDoubleTapSupported
        menu.addItem(continuousItem)
        return menu
    }

    func triggerSubmenu(_ triggers: [TriggerKey]) -> NSMenu {
        let menu = NSMenu()
        for trigger in triggers {
            addTriggerItem(trigger, to: menu)
        }
        return menu
    }

    func addTriggerItem(_ trigger: TriggerKey, to menu: NSMenu) {
        let menuItem = item(title: strings.triggerLabel(trigger), action: #selector(selectTrigger(_:)))
        menuItem.representedObject = trigger.identifier
        menuItem.state = trigger == settings.triggerKey ? .on : .off
        menu.addItem(menuItem)
    }

    func durationMenu() -> NSMenu {
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

    func hudStyleMenu() -> NSMenu {
        let menu = NSMenu(title: strings.hudStyle)
        for style in HUDVisualStyleAvailability.availableStyles() {
            let menuItem = item(title: style.displayName(in: settings.uiLanguage), action: #selector(selectHUDStyle(_:)))
            menuItem.representedObject = style.rawValue
            menuItem.state = style == settings.hudVisualStyle ? .on : .off
            menu.addItem(menuItem)
        }
        return menu
    }

    func hudMessageDurationMenu() -> NSMenu {
        let menu = NSMenu(title: strings.hudMessageDuration)
        for duration in HUDMessageDuration.allCases {
            let menuItem = item(title: duration.displayName, action: #selector(selectHUDMessageDuration(_:)), tooltip: strings.tooltip(.hudMessageDuration))
            menuItem.representedObject = duration.rawValue
            menuItem.state = duration == settings.hudMessageDuration ? .on : .off
            menu.addItem(menuItem)
        }
        return menu
    }

    func hudRevealDelayMenu() -> NSMenu {
        let menu = NSMenu(title: strings.hudRevealDelay)
        for delay in HUDRevealDelay.allCases {
            let menuItem = item(title: delay.displayName(in: settings.uiLanguage), action: #selector(selectHUDRevealDelay(_:)), tooltip: strings.tooltip(.hudRevealDelay))
            menuItem.representedObject = delay.rawValue
            menuItem.state = delay == settings.hudRevealDelay ? .on : .off
            menu.addItem(menuItem)
        }
        return menu
    }

    func displayHintsMenu() -> NSMenu {
        let menu = NSMenu(title: strings.displayHints)
        let livePreview = item(
            title: strings.liveASRPreviewTitle(enabled: settings.liveASRPreviewEnabled),
            action: #selector(toggleLiveASRPreview),
            tooltip: strings.tooltip(.liveASRPreview)
        )
        livePreview.state = settings.liveASRPreviewEnabled ? .on : .off
        menu.addItem(livePreview)
        menu.addItem(NSMenuItem.separator())
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

    func configurationMenu() -> NSMenu {
        let menu = NSMenu(title: strings.configuration)
        menu.addItem(submenuItem(strings.apiSourceTitle(config, mode: settings.pipelineMode), submenu: apiSourceMenu()))
        menu.addItem(submenuItem(
            strings.modelConfigurationTitle(mode: settings.pipelineMode, model: currentPipelineModel),
            submenu: modelConfigurationMenu()
        ))
        menu.addItem(submenuItem(strings.systemASR, submenu: systemASRMenu()))
        menu.addItem(submenuItem(strings.latencyIntervalTitle(config.latencySettings.interval), submenu: latencyIntervalMenu()))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(title: strings.openConfigFile, action: #selector(openConfigFile), tooltip: strings.tooltip(.openConfigFile)))
        menu.addItem(item(title: strings.reloadConfig, action: #selector(reloadConfig), tooltip: strings.tooltip(.reloadConfig)))
        menu.addItem(item(title: strings.refreshModels, action: #selector(refreshModelsAction), tooltip: strings.tooltip(.refreshModels)))
        menu.addItem(item(title: connectionCheckTitle, action: #selector(checkConnectionAndLatency), tooltip: strings.tooltip(.connectionCheck)))
        return menu
    }

    func apiSourceMenu() -> NSMenu {
        let menu = NSMenu(title: strings.apiSource)
        let supportingSourceIDs = modelAvailabilityIndex.sourceIDsSupporting(currentPipelineModel, mode: settings.pipelineMode)
        let hasModelMeasurements = modelAvailabilityIndex.hasMeasurements
        let systemASROnly = settings.pipelineMode == .systemASROnly
        let autoItem = item(
            title: strings.autoAPISourceMenuItem(resolvedSourceID: config.resolvedSourceID),
            action: #selector(selectAPISource(_:)),
            tooltip: systemASROnly ? strings.tooltip(.systemASROnlyMode) : strings.tooltip(.apiSourceAuto)
        )
        autoItem.representedObject = MimoConfig.autoSourceID
        autoItem.state = config.activeSourceID == MimoConfig.autoSourceID ? .on : .off
        autoItem.isEnabled = !systemASROnly && (!hasModelMeasurements || !supportingSourceIDs.isEmpty)
        menu.addItem(autoItem)
        menu.addItem(NSMenuItem.separator())
        for source in config.sourceSummaries {
            let supportsCurrentModel = !systemASROnly && (!hasModelMeasurements || supportingSourceIDs.contains(source.id))
            let menuItem = item(
                title: strings.apiSourceMenuItem(source, latency: sourceLatencyResults[source.id]),
                action: #selector(selectAPISource(_:)),
                tooltip: systemASROnly
                    ? strings.tooltip(.systemASROnlyMode)
                    : (supportsCurrentModel ? strings.tooltip(.apiSourceAvailable) : strings.apiSourceDoesNotExposeCurrentModel(currentPipelineModel))
            )
            menuItem.representedObject = source.id
            menuItem.state = source.id == config.activeSourceID ? .on : .off
            menuItem.isEnabled = supportsCurrentModel
            menu.addItem(menuItem)
        }
        if config.sourceSummaries.isEmpty {
            menu.addItem(disabledItem(strings.configWarning("Config file missing")))
        }
        menu.addItem(NSMenuItem.separator())
        let systemOnlyItem = item(
            title: strings.useSystemASROnly,
            action: #selector(toggleSystemASROnlyMode),
            tooltip: strings.tooltip(.systemASROnlyMode)
        )
        systemOnlyItem.state = systemASROnly ? .on : .off
        menu.addItem(systemOnlyItem)
        return menu
    }

    func latencyIntervalMenu() -> NSMenu {
        let menu = NSMenu(title: strings.latencyInterval)
        for interval in ConfigLatencyInterval.allCases {
            let menuItem = item(title: strings.latencyIntervalLabel(interval), action: #selector(selectLatencyInterval(_:)), tooltip: strings.tooltip(.latency))
            menuItem.representedObject = interval.rawValue
            menuItem.state = interval == config.latencySettings.interval ? .on : .off
            menu.addItem(menuItem)
        }
        return menu
    }

    func permissionsMenu(snapshot: PermissionSnapshot) -> NSMenu {
        let menu = NSMenu(title: strings.permissions)
        menu.addItem(PermissionMenuPresenter(strings: strings, uiLanguage: settings.uiLanguage).summaryItem(snapshot))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(title: strings.requestAllPermissions, action: #selector(requestAllPermissions), tooltip: strings.tooltip(.requestAllPermissions)))
        menu.addItem(item(title: strings.requestMicrophone, action: #selector(requestMicrophonePermission), tooltip: strings.tooltip(.requestMicrophone)))
        menu.addItem(item(title: strings.requestAccessibility, action: #selector(requestAccessibilityPermission), tooltip: strings.tooltip(.requestAccessibility)))
        menu.addItem(item(title: strings.requestInputMonitoring, action: #selector(requestInputMonitoringPermission), tooltip: strings.tooltip(.requestInputMonitoring)))
        menu.addItem(item(title: strings.requestSpeechRecognition, action: #selector(requestSpeechRecognitionPermission), tooltip: strings.tooltip(.requestSpeechRecognition)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(title: strings.openMicrophoneSettings, action: #selector(openMicrophoneSettings)))
        menu.addItem(item(title: strings.openAccessibilitySettings, action: #selector(openAccessibilitySettings)))
        menu.addItem(item(title: strings.openInputMonitoringSettings, action: #selector(openInputMonitoringSettings)))
        menu.addItem(item(title: strings.openSpeechRecognitionSettings, action: #selector(openSpeechRecognitionSettings)))
        return menu
    }

    func tooltip(for descriptor: TranscriptionStyleDescriptor) -> String {
        strings.transcriptionStyleTooltip(descriptor)
    }

    func item(title: String, action: Selector?, tooltip: String? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        menuItem.toolTip = tooltip
        return menuItem
    }

    func disabledItem(_ title: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.isEnabled = false
        return menuItem
    }

    func submenuItem(_ title: String, submenu: NSMenu, tooltip: String? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.submenu = submenu
        menuItem.toolTip = tooltip
        return menuItem
    }

    @objc func toggleGlobalStop() {
        MenuActionRouter(coordinator: self).toggleGlobalStop()
    }

    @objc func toggleAutoInsert() {
        MenuActionRouter(coordinator: self).toggleAutoInsert()
    }

    @objc func toggleLiveASRPreview() {
        MenuActionRouter(coordinator: self).toggleLiveASRPreview()
    }

    @objc func selectPipelineMode(_ sender: NSMenuItem) {
        MenuActionRouter(coordinator: self).selectPipelineMode(sender)
    }

    @objc func selectPipelineModel(_ sender: NSMenuItem) {
        MenuActionRouter(coordinator: self).selectPipelineModel(sender)
    }

    @objc func selectSystemASREngine(_ sender: NSMenuItem) {
        MenuActionRouter(coordinator: self).selectSystemASREngine(sender)
    }

    @objc func toggleSystemASRKeywordHints() {
        MenuActionRouter(coordinator: self).toggleSystemASRKeywordHints()
    }

    @objc func toggleSystemASROnlyMode() {
        MenuActionRouter(coordinator: self).toggleSystemASROnlyMode()
    }

    func persistModelAndPipelineSettings(activeSourceID: String? = nil) {
        markInternalConfigWrite()
        _ = configStore.saveModelAndPipelineSettings(
            inputAudioModel: settings.selectedModel,
            textLLMModel: settings.selectedTextLLMModel,
            pipelineMode: settings.pipelineMode,
            systemASRSettings: SystemASRSettings(
                engine: settings.systemASREngine,
                keywordHintsEnabled: settings.systemASRKeywordHintsEnabled
            ),
            activeSourceID: activeSourceID,
            uiLanguage: settings.uiLanguage
        )
        client = makeClient(config: config)
    }

    func selectObservedModelIfNeeded(for mode: TranscriptionPipelineMode) {
        guard mode == .inputAudio else { return }
        let available = modelAvailabilityIndex.availableModels(for: mode)
        guard !available.isEmpty else { return }
        if !available.contains(settings.selectedModel) {
            settings.selectedModel = available[0]
        }
    }

    func preferredActiveSourceID(for model: AllowedSpeechModel, mode: TranscriptionPipelineMode) -> String? {
        guard mode.requiresModelAPI else { return nil }
        let sourceIDs = modelAvailabilityIndex.sourceIDsSupporting(model, mode: mode)
        guard !sourceIDs.isEmpty else { return nil }
        if sourceIDs.count == 1 {
            return sourceIDs[0]
        }
        if config.activeSourceID == MimoConfig.autoSourceID || sourceIDs.contains(config.activeSourceID) {
            return config.activeSourceID
        }
        return MimoConfig.autoSourceID
    }

    @objc func selectLanguage(_ sender: NSMenuItem) {
        MenuActionRouter(coordinator: self).selectLanguage(sender)
    }

    @objc func selectStyle(_ sender: NSMenuItem) {
        MenuActionRouter(coordinator: self).selectStyle(sender)
    }

    @objc func toggleKeywordHints() {
        MenuActionRouter(coordinator: self).toggleKeywordHints()
    }

    @objc func toggleKeywordGroup(_ sender: NSMenuItem) {
        MenuActionRouter(coordinator: self).toggleKeywordGroup(sender)
    }

    @objc func selectTrigger(_ sender: NSMenuItem) {
        MenuActionRouter(coordinator: self).selectTrigger(sender)
    }

    @objc func toggleContinuousRecordingDoubleTap() {
        MenuActionRouter(coordinator: self).toggleContinuousRecordingDoubleTap()
    }

    func applyTriggerSelection(_ trigger: TriggerKey) {
        resetContinuousRecordingTriggerState()
        settings.triggerKey = trigger
        eventTap.update(triggerKey: trigger)
        if settings.listeningEnabled, !globalStopActive {
            startListening(showFailureHUD: true)
        }
        _ = persistCurrentPreferences()
        rebuildMenu()
    }

    func beginTriggerCapture(view: TriggerCaptureMenuView) {
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

    func handleTriggerCaptureSignal(_ signal: TriggerCaptureSignal) {
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

    func cancelTriggerCapture(updateView: Bool = true, restartListening: Bool = true) {
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

    @objc func selectDuration(_ sender: NSMenuItem) {
        MenuActionRouter(coordinator: self).selectDuration(sender)
    }

    @objc func selectMinDuration(_ sender: NSMenuItem) {
        MenuActionRouter(coordinator: self).selectMinDuration(sender)
    }

    @objc func selectHUDStyle(_ sender: NSMenuItem) {
        MenuActionRouter(coordinator: self).selectHUDStyle(sender)
    }

    @objc func selectHUDMessageDuration(_ sender: NSMenuItem) {
        MenuActionRouter(coordinator: self).selectHUDMessageDuration(sender)
    }

    @objc func selectHUDRevealDelay(_ sender: NSMenuItem) {
        MenuActionRouter(coordinator: self).selectHUDRevealDelay(sender)
    }
}
