import Foundation

@MainActor
final class ListeningLifecycleCoordinator {
    private unowned let coordinator: AppCoordinator

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func stopAllFeatures() {
        let priorState = String(describing: coordinator.state)
        coordinator.recordingTimingRuntime.maxRecordingTimer.cancel()
        coordinator.resetListeningHUDRevealState()
        let stopWasPending = coordinator.cancelPendingRecordingStop()
        coordinator.transcriptionTask?.cancel()
        coordinator.pendingTranscription?.liveASRFinalTask?.cancel()
        coordinator.transcriptionTask = nil
        if RecordingStopCancellationPlanner.shouldCancelRecordingSource(recordingStopInProgress: stopWasPending) {
            coordinator.recordingSource.cancel()
        }
        coordinator.cancelLiveASRSession()
        coordinator.eventTap.setCancellationActive(false)
        coordinator.eventTap.stop()
        coordinator.hud.hide()
        coordinator.actionPanel.cancel()
        coordinator.recordingFocus = nil
        coordinator.recordingStartDate = nil
        coordinator.pendingTranscription = nil
        coordinator.stopPermissionReadinessPolling()
        coordinator.stopPermissionDriftMonitoring()
        coordinator.state = .idle
        coordinator.settings.listeningEnabled = false
        coordinator.globalStopActive = true
        coordinator.stopReason = .manual
        coordinator.settings.stopReason = .manual
        coordinator.eventTap.setTriggerSuppressionEnabled(false)
        coordinator.tapStatus = coordinator.strings.stopped
        coordinator.hud.showTransientStatus(coordinator.strings.stopped, duration: coordinator.warningDuration)
        coordinator.recordLocalDiagnostic(
            stage: "global_stop",
            errorKind: "manual_stop",
            details: [
                "previous_state": priorState,
                "listening_enabled": "false",
                "auto_insert_paused": "true"
            ]
        )
        coordinator.rebuildMenu()
    }

    func reenable() {
        coordinator.globalStopActive = false
        coordinator.stopReason = nil
        coordinator.settings.stopReason = nil
        coordinator.stopPermissionReadinessPolling()
        coordinator.settings.listeningEnabled = true
        startListening(showFailureHUD: true)
        if !coordinator.globalStopActive {
            coordinator.hud.showTransientStatus(coordinator.strings.reenabled, duration: coordinator.warningDuration)
            coordinator.recordLocalDiagnostic(stage: "global_reenabled", details: ["auto_insert_paused": "false"])
        }
        coordinator.rebuildMenu()
        coordinator.applyPendingConfigHotReloadIfNeeded()
    }

    func startListening(showFailureHUD: Bool = false) {
        guard !coordinator.globalStopActive else {
            coordinator.tapStatus = coordinator.strings.stopped
            return
        }
        let snapshot = PermissionChecker.snapshot()
        coordinator.lastPermissionSnapshot = snapshot
        let otherInstanceCount = coordinator.otherRunningOmniVoiceApplications().count
        guard PermissionListeningStartupPlanner.shouldStartListening(
            listeningEnabled: coordinator.settings.listeningEnabled,
            globalStopActive: coordinator.globalStopActive,
            permissions: snapshot,
            hasOtherRunningInstance: otherInstanceCount > 0
        ) else {
            coordinator.eventTap.setTriggerSuppressionEnabled(false)
            coordinator.eventTap.stop()
            coordinator.tapStatus = coordinator.strings.listeningUnavailable()
            if otherInstanceCount > 0 {
                coordinator.settings.listeningEnabled = false
                coordinator.globalStopActive = true
                coordinator.stopReason = .manual
                coordinator.settings.stopReason = .manual
                coordinator.tapStatus = coordinator.strings.stopped
                coordinator.recordLocalDiagnostic(
                    stage: "listening_start_blocked",
                    errorKind: "single_instance_conflict",
                    details: coordinator.diagnosticRuntimeDetails(["other_instance_count": "\(otherInstanceCount)"])
                )
            } else if !snapshot.allRequiredGranted {
                enterPermissionBlockedStop()
            }
            if showFailureHUD {
                coordinator.hud.showWarningStatus(coordinator.strings.permissionIssue, duration: coordinator.warningDuration)
            }
            coordinator.rebuildMenu()
            return
        }
        coordinator.eventTapFailureHUDEnabled = showFailureHUD
        coordinator.eventTap.update(triggerKey: coordinator.settings.triggerKey)
        coordinator.eventTap.updateWatchdogTimeout(seconds: TimeInterval(coordinator.settings.maxRecordingDuration.rawValue + 5))
        coordinator.updateEventTapTriggerSuppression()
        let started = coordinator.eventTap.start()
        coordinator.tapStatus = started ? coordinator.strings.listeningWithTrigger(coordinator.settings.triggerKey) : coordinator.strings.listeningUnavailable()
        if started {
            coordinator.schedulePermissionDriftMonitoringIfNeeded()
        }
        if !started {
            if !snapshot.allRequiredGranted {
                enterPermissionBlockedStop()
            }
            if showFailureHUD {
                coordinator.hud.showWarningStatus(coordinator.strings.permissionIssue, duration: coordinator.warningDuration)
            }
        }
    }

    func enterPermissionBlockedStop(recordDiagnostic: Bool = true) {
        coordinator.recordingTimingRuntime.maxRecordingTimer.cancel()
        coordinator.resetListeningHUDRevealState()
        let stopWasPending = coordinator.cancelPendingRecordingStop()
        coordinator.transcriptionTask?.cancel()
        coordinator.pendingTranscription?.liveASRFinalTask?.cancel()
        coordinator.transcriptionTask = nil
        if RecordingStopCancellationPlanner.shouldCancelRecordingSource(recordingStopInProgress: stopWasPending) {
            coordinator.recordingSource.cancel()
        }
        coordinator.cancelLiveASRSession()
        coordinator.eventTap.setCancellationActive(false)
        coordinator.eventTap.setTriggerSuppressionEnabled(false)
        coordinator.eventTap.stop()
        coordinator.stopPermissionDriftMonitoring()
        coordinator.state = .idle
        coordinator.settings.listeningEnabled = false
        coordinator.globalStopActive = true
        coordinator.stopReason = .permissionBlocked
        coordinator.settings.stopReason = .permissionBlocked
        coordinator.tapStatus = coordinator.strings.listeningUnavailable()
        coordinator.schedulePermissionReadinessPollingIfNeeded()
        if recordDiagnostic {
            coordinator.recordLocalDiagnostic(stage: "permission_blocked_stop", errorKind: "permissions_missing")
        }
    }
}
