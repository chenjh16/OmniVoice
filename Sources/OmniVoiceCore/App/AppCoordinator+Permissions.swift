import AppKit
import Foundation

extension AppCoordinator {
    func stopAllFeatures() {
        listeningLifecycleCoordinator.stopAllFeatures()
    }

    func reenable() {
        listeningLifecycleCoordinator.reenable()
    }

    @objc func requestAllPermissions() {
        permissionCoordinator.requestAllPermissions()
    }

    @objc func requestMicrophonePermission() {
        permissionCoordinator.requestMicrophonePermission()
    }

    @objc func requestAccessibilityPermission() {
        permissionCoordinator.requestAccessibilityPermission()
    }

    @objc func requestInputMonitoringPermission() {
        permissionCoordinator.requestInputMonitoringPermission()
    }

    @objc func requestSpeechRecognitionPermission() {
        permissionCoordinator.requestSpeechRecognitionPermission()
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
        await permissionCoordinator.runStartupPermissionGuideIfNeeded()
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
        listeningLifecycleCoordinator.startListening(showFailureHUD: showFailureHUD)
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
        listeningLifecycleCoordinator.enterPermissionBlockedStop(recordDiagnostic: recordDiagnostic)
    }

    func schedulePermissionReadinessPollingIfNeeded() {
        guard stopReason == .permissionBlocked else { return }
        guard permissionPollingRuntime.readinessTimer.timer == nil else { return }
        let timer = permissionPollingRuntime.readinessTimer.schedule(interval: 1.5, repeats: true) { [weak self] in
            self?.pollPermissionReadiness()
        }
        timer.tolerance = 0.3
    }

    func stopPermissionReadinessPolling() {
        permissionPollingRuntime.readinessTimer.cancel()
    }

    func schedulePermissionDriftMonitoringIfNeeded() {
        guard permissionPollingRuntime.driftTimer.timer == nil else { return }
        let timer = permissionPollingRuntime.driftTimer.schedule(interval: 2.0, repeats: true) { [weak self] in
            self?.pollPermissionDrift()
        }
        timer.tolerance = 0.4
    }

    func stopPermissionDriftMonitoring() {
        permissionPollingRuntime.driftTimer.cancel()
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

}
