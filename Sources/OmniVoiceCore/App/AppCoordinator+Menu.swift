import AppKit
import Foundation

extension AppCoordinator {
    func menuWillOpen(_ menu: NSMenu) {
        handlePermissionReadiness(PermissionChecker.snapshot())
        reloadExternalASRPlugins()
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

    @objc func toggleGlobalStop() {
        menuActionRouter.toggleGlobalStop()
    }

    @objc func toggleAutoInsert() {
        menuActionRouter.toggleAutoInsert()
    }

    @objc func toggleLiveASRPreview() {
        menuActionRouter.toggleLiveASRPreview()
    }

    @objc func selectPipelineMode(_ sender: NSMenuItem) {
        menuActionRouter.selectPipelineMode(sender)
    }

    @objc func selectPipelineModel(_ sender: NSMenuItem) {
        menuActionRouter.selectPipelineModel(sender)
    }

    @objc func selectSystemASREngine(_ sender: NSMenuItem) {
        menuActionRouter.selectSystemASREngine(sender)
    }

    @objc func selectExternalASRProvider(_ sender: NSMenuItem) {
        menuActionRouter.selectExternalASRProvider(sender)
    }

    @objc func toggleSystemASRKeywordHints() {
        menuActionRouter.toggleSystemASRKeywordHints()
    }

    @objc func toggleSystemASROnlyMode() {
        menuActionRouter.toggleSystemASROnlyMode()
    }

    func persistModelAndPipelineSettings(activeSourceID: String? = nil) {
        markInternalConfigWrite()
        _ = configStore.saveModelAndPipelineSettings(
            inputAudioModel: settings.selectedModel,
            textLLMModel: settings.selectedTextLLMModel,
            pipelineMode: settings.pipelineMode,
            systemASRSettings: SystemASRSettings(
                engine: settings.systemASREngine,
                keywordHintsEnabled: settings.systemASRKeywordHintsEnabled,
                externalASR: ExternalASRSettings(providerID: settings.externalASRProviderID)
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
        menuActionRouter.selectLanguage(sender)
    }

    @objc func selectStyle(_ sender: NSMenuItem) {
        menuActionRouter.selectStyle(sender)
    }

    @objc func toggleKeywordHints() {
        menuActionRouter.toggleKeywordHints()
    }

    @objc func toggleKeywordGroup(_ sender: NSMenuItem) {
        menuActionRouter.toggleKeywordGroup(sender)
    }

    @objc func selectTrigger(_ sender: NSMenuItem) {
        menuActionRouter.selectTrigger(sender)
    }

    @objc func toggleContinuousRecordingDoubleTap() {
        menuActionRouter.toggleContinuousRecordingDoubleTap()
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
        triggerCaptureRuntime.pausedListening = decision.shouldPauseNormalTap
        if decision.shouldPauseNormalTap {
            eventTap.stop()
        }
        triggerCaptureRuntime.view = view
        view.beginCapture()
        guard triggerCapture.start() else {
            view.showRejected(strings.inputMonitoringManual)
            hud.showWarningStatus(strings.inputMonitoringManual, duration: warningDuration)
            cancelTriggerCapture(updateView: false, restartListening: true)
            return
        }
        triggerCaptureRuntime.timeoutTimer.schedule(interval: 8.0, repeats: false) { [weak self] in
            self?.cancelTriggerCapture()
        }
    }

    func handleTriggerCaptureSignal(_ signal: TriggerCaptureSignal) {
        guard triggerCapture.isRunning else { return }
        switch signal {
        case .captured(let candidate):
            let view = triggerCaptureRuntime.view
            cancelTriggerCapture(updateView: false, restartListening: false)
            view?.showSelected(strings.triggerLabel(candidate))
            applyTriggerSelection(candidate)
        case .cancelled:
            cancelTriggerCapture()
        case .rejected:
            triggerCaptureRuntime.view?.showRejected(strings.triggerRecordingRejected)
        case .failed:
            triggerCaptureRuntime.view?.showRejected(strings.inputMonitoringManual)
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
        triggerCaptureRuntime.timeoutTimer.cancel()
        if updateView {
            triggerCaptureRuntime.view?.endCapture()
        }
        triggerCaptureRuntime.view = nil
        let shouldRestartListening = TriggerCaptureSessionPlanner.finish(
            pausedNormalTap: triggerCaptureRuntime.pausedListening,
            restartListening: restartListening,
            listeningEnabled: settings.listeningEnabled && !globalStopActive
        ).shouldRestoreNormalTap
        triggerCaptureRuntime.pausedListening = false
        if shouldRestartListening {
            startListening(showFailureHUD: false)
        }
    }

    @objc func selectDuration(_ sender: NSMenuItem) {
        menuActionRouter.selectDuration(sender)
    }

    @objc func selectMinDuration(_ sender: NSMenuItem) {
        menuActionRouter.selectMinDuration(sender)
    }

    @objc func selectHUDStyle(_ sender: NSMenuItem) {
        menuActionRouter.selectHUDStyle(sender)
    }

    @objc func selectHUDMessageDuration(_ sender: NSMenuItem) {
        menuActionRouter.selectHUDMessageDuration(sender)
    }

    @objc func selectHUDRevealDelay(_ sender: NSMenuItem) {
        menuActionRouter.selectHUDRevealDelay(sender)
    }
}

extension AppCoordinator: MenuActionRoutingRuntime {}
