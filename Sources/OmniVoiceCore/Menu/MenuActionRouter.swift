import AppKit
import Foundation

@MainActor
final class MenuActionRouter {
    private unowned let coordinator: AppCoordinator

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func toggleGlobalStop() {
        if coordinator.globalStopActive || !coordinator.settings.listeningEnabled {
            coordinator.reenable()
        } else {
            coordinator.stopAllFeatures()
        }
    }

    func toggleAutoInsert() {
        coordinator.settings.autoInsert.toggle()
        _ = coordinator.persistCurrentPreferences()
        coordinator.rebuildMenu()
    }

    func toggleLiveASRPreview() {
        coordinator.settings.liveASRPreviewEnabled.toggle()
        _ = coordinator.persistCurrentPreferences()
        coordinator.rebuildMenu()
    }

    func selectPipelineMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = TranscriptionPipelineMode(rawValue: raw) else { return }
        coordinator.settings.pipelineMode = mode
        coordinator.selectObservedModelIfNeeded(for: mode)
        coordinator.persistModelAndPipelineSettings(activeSourceID: coordinator.preferredActiveSourceID(
            for: coordinator.currentPipelineModel,
            mode: mode
        ))
        coordinator.rebuildMenu()
    }

    func selectPipelineModel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let model = AllowedSpeechModel(rawValue: raw) else { return }
        if coordinator.settings.pipelineMode == .inputAudio {
            coordinator.settings.selectedModel = model
        } else {
            coordinator.settings.selectedTextLLMModel = model
        }
        coordinator.persistModelAndPipelineSettings(activeSourceID: coordinator.preferredActiveSourceID(
            for: model,
            mode: coordinator.settings.pipelineMode
        ))
        coordinator.rebuildMenu()
    }

    func selectSystemASREngine(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let engine = SystemASREngine(rawValue: raw) else { return }
        coordinator.settings.systemASREngine = engine
        coordinator.persistModelAndPipelineSettings()
        coordinator.rebuildMenu()
    }

    func toggleSystemASRKeywordHints() {
        coordinator.settings.systemASRKeywordHintsEnabled.toggle()
        coordinator.persistModelAndPipelineSettings()
        coordinator.rebuildMenu()
    }

    func toggleSystemASROnlyMode() {
        coordinator.settings.pipelineMode = coordinator.settings.pipelineMode == .systemASROnly
            ? .inputAudio
            : .systemASROnly
        coordinator.persistModelAndPipelineSettings()
        coordinator.rebuildMenu()
    }

    func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let language = UILanguage(rawValue: raw) else { return }
        coordinator.settings.uiLanguage = language
        _ = coordinator.persistCurrentPreferences()
        if coordinator.settings.listeningEnabled {
            coordinator.tapStatus = coordinator.eventTap.isRunning
                ? coordinator.strings.listeningWithTrigger(coordinator.settings.triggerKey)
                : coordinator.strings.listeningUnavailable()
        }
        coordinator.rebuildMenu()
        coordinator.applyPendingConfigHotReloadIfNeeded()
    }

    func selectStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        coordinator.settings.transcriptionStyleSelection = TranscriptionStyleSelection(rawValue: raw)
        _ = coordinator.persistCurrentPreferences()
        coordinator.rebuildMenu()
    }

    func toggleKeywordHints() {
        let plan = KeywordHintSelectionPlanner.toggleEnabled(
            isEnabled: coordinator.settings.keywordHintsEnabled,
            selectedIDs: coordinator.settings.enabledKeywordGroupIDs,
            availableIDs: coordinator.config.keywordGroups.map(\.id)
        )
        coordinator.settings.updatePreferences {
            $0.updating(
                keywordHintsEnabled: plan.isEnabled,
                enabledKeywordGroupIDs: plan.selectedIDs
            )
        }
        _ = coordinator.persistCurrentPreferences()
        coordinator.rebuildMenu()
    }

    func toggleKeywordGroup(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              coordinator.config.keywordGroups.contains(where: { $0.id == id }) else { return }
        let plan = KeywordHintSelectionPlanner.toggleGroup(
            id,
            selectedIDs: coordinator.settings.enabledKeywordGroupIDs,
            availableIDs: coordinator.config.keywordGroups.map(\.id)
        )
        coordinator.settings.updatePreferences {
            $0.updating(
                keywordHintsEnabled: plan.isEnabled,
                enabledKeywordGroupIDs: plan.selectedIDs
            )
        }
        _ = coordinator.persistCurrentPreferences()
        coordinator.rebuildMenu()
    }

    func selectTrigger(_ sender: NSMenuItem) {
        let trigger = TriggerKey.candidate(identifier: sender.representedObject as? String)
        coordinator.cancelTriggerCapture(restartListening: false)
        coordinator.applyTriggerSelection(trigger)
    }

    func toggleContinuousRecordingDoubleTap() {
        guard coordinator.continuousRecordingDoubleTapSupported else {
            coordinator.hud.showTransientStatus(
                coordinator.strings.continuousRecordingUnsupportedForTrigger(coordinator.settings.triggerKey),
                duration: coordinator.warningDuration
            )
            coordinator.rebuildMenu()
            return
        }
        coordinator.settings.continuousRecordingDoubleTapEnabled.toggle()
        coordinator.resetContinuousRecordingTriggerState()
        _ = coordinator.persistCurrentPreferences()
        coordinator.rebuildMenu()
    }

    func selectDuration(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Int else { return }
        coordinator.settings.maxRecordingDuration = MaxRecordingDuration.safeSelection(seconds)
        coordinator.eventTap.updateWatchdogTimeout(seconds: TimeInterval(coordinator.settings.maxRecordingDuration.rawValue + 5))
        _ = coordinator.persistCurrentPreferences()
        coordinator.rebuildMenu()
    }

    func selectMinDuration(_ sender: NSMenuItem) {
        guard let milliseconds = sender.representedObject as? Int else { return }
        coordinator.settings.minRecordingDuration = MinRecordingDuration.safeSelection(milliseconds)
        _ = coordinator.persistCurrentPreferences()
        coordinator.rebuildMenu()
    }

    func selectHUDStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        coordinator.settings.hudVisualStyle = HUDVisualStyleAvailability.sanitizedSelection(HUDVisualStyle.safeSelection(raw))
        coordinator.hud.setVisualStyle(coordinator.settings.hudVisualStyle)
        coordinator.actionPanel.setVisualStyle(coordinator.settings.hudVisualStyle)
        _ = coordinator.persistCurrentPreferences()
        coordinator.rebuildMenu()
    }

    func selectHUDMessageDuration(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Int else { return }
        coordinator.settings.hudMessageDuration = HUDMessageDuration.safeSelection(seconds)
        _ = coordinator.persistCurrentPreferences()
        coordinator.rebuildMenu()
    }

    func selectHUDRevealDelay(_ sender: NSMenuItem) {
        guard let milliseconds = sender.representedObject as? Int else { return }
        coordinator.settings.hudRevealDelay = HUDRevealDelay.safeSelection(milliseconds)
        _ = coordinator.persistCurrentPreferences()
        coordinator.rebuildMenu()
    }
}
