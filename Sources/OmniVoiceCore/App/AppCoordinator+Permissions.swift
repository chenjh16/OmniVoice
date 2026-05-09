import AppKit
import Foundation

extension AppCoordinator {
    func stopAllFeatures() {
        ListeningLifecycleCoordinator(coordinator: self).stopAllFeatures()
    }

    func reenable() {
        ListeningLifecycleCoordinator(coordinator: self).reenable()
    }

    @objc func requestAllPermissions() {
        PermissionCoordinator(coordinator: self).requestAllPermissions()
    }

    @objc func requestMicrophonePermission() {
        PermissionCoordinator(coordinator: self).requestMicrophonePermission()
    }

    @objc func requestAccessibilityPermission() {
        PermissionCoordinator(coordinator: self).requestAccessibilityPermission()
    }

    @objc func requestInputMonitoringPermission() {
        PermissionCoordinator(coordinator: self).requestInputMonitoringPermission()
    }

    @objc func requestSpeechRecognitionPermission() {
        PermissionCoordinator(coordinator: self).requestSpeechRecognitionPermission()
    }

    @objc func openMicrophoneSettings() {
        PermissionChecker.openMicrophoneSettings()
    }

    @objc func openAccessibilitySettings() {
        PermissionChecker.openAccessibilitySettings()
    }

    @objc func openInputMonitoringSettings() {
        PermissionChecker.openInputMonitoringSettings()
    }

    @objc func openSpeechRecognitionSettings() {
        PermissionChecker.openSpeechRecognitionSettings()
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    @objc func restartApp() {
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

    func runStartupPermissionGuideIfNeeded() async {
        await PermissionCoordinator(coordinator: self).runStartupPermissionGuideIfNeeded()
    }

    func applyPersistedStoppedState() {
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

    func startListening(showFailureHUD: Bool = false) {
        ListeningLifecycleCoordinator(coordinator: self).startListening(showFailureHUD: showFailureHUD)
    }

    func normalizeHUDStyleAvailability() {
        let sanitized = HUDVisualStyleAvailability.sanitizedSelection(settings.hudVisualStyle)
        if sanitized != settings.hudVisualStyle {
            settings.hudVisualStyle = sanitized
        }
    }

    @discardableResult
    func handlePermissionReadiness(_ snapshot: PermissionSnapshot) -> Bool {
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

    func enterPermissionBlockedStop(recordDiagnostic: Bool = true) {
        ListeningLifecycleCoordinator(coordinator: self).enterPermissionBlockedStop(recordDiagnostic: recordDiagnostic)
    }

    func schedulePermissionReadinessPollingIfNeeded() {
        guard stopReason == .permissionBlocked else { return }
        guard permissionReadinessTimer == nil else { return }
        permissionReadinessTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPermissionReadiness()
            }
        }
        permissionReadinessTimer?.tolerance = 0.3
    }

    func stopPermissionReadinessPolling() {
        permissionReadinessTimer?.invalidate()
        permissionReadinessTimer = nil
    }

    func schedulePermissionDriftMonitoringIfNeeded() {
        guard permissionDriftTimer == nil else { return }
        permissionDriftTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPermissionDrift()
            }
        }
        permissionDriftTimer?.tolerance = 0.4
    }

    func stopPermissionDriftMonitoring() {
        permissionDriftTimer?.invalidate()
        permissionDriftTimer = nil
    }

    func pollPermissionDrift() {
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

    func pollPermissionReadiness() {
        guard stopReason == .permissionBlocked else {
            stopPermissionReadinessPolling()
            return
        }
        if handlePermissionReadiness(PermissionChecker.snapshot()) {
            rebuildMenu()
        }
    }

    func handleEventTapSignal(_ signal: EventTapSignal) {
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
            handleRecordingTriggerDown()
        case .triggerUp:
            eventTap.acknowledgeMainSignal()
            recordLocalDiagnostic(
                stage: "trigger_up_received",
                details: [
                    "trigger": settings.triggerKey.identifier,
                    "state": String(describing: state)
                ]
            )
            handleRecordingTriggerUp()
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

    func handleEventTapDisabled() {
        resetContinuousRecordingTriggerState()
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

    func handleTriggerAckTimeout() {
        resetContinuousRecordingTriggerState()
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil
        resetListeningHUDRevealState()
        let stopWasPending = cancelPendingRecordingStop()
        transcriptionTask?.cancel()
        pendingTranscription?.liveASRFinalTask?.cancel()
        transcriptionTask = nil
        if RecordingStopCancellationPlanner.shouldCancelRecordingSource(recordingStopInProgress: stopWasPending) {
            recordingSource.cancel()
        }
        cancelLiveASRSession()
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

    func performEmergencyRescueExit() {
        resetContinuousRecordingTriggerState()
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil
        resetListeningHUDRevealState()
        let stopWasPending = cancelPendingRecordingStop()
        transcriptionTask?.cancel()
        pendingTranscription?.liveASRFinalTask?.cancel()
        transcriptionTask = nil
        if RecordingStopCancellationPlanner.shouldCancelRecordingSource(recordingStopInProgress: stopWasPending) {
            recordingSource.cancel()
        }
        cancelLiveASRSession()
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
}
