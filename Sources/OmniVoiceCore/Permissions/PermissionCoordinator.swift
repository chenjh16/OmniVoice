import AppKit
import Foundation

@MainActor
final class PermissionCoordinator {
    private unowned let coordinator: AppCoordinator

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
    }

    func requestAllPermissions() {
        Task { await runPermissionGuide(isManualRequest: true) }
    }

    func requestMicrophonePermission() {
        Task {
            _ = await PermissionChecker.requestMicrophone()
            restartListeningAfterPermissionChange(autoEnabled: coordinator.handlePermissionReadiness(PermissionChecker.snapshot()))
            coordinator.rebuildMenu()
        }
    }

    func requestAccessibilityPermission() {
        Task {
            let outcome = await requestAccessibilityPermissionAndWaitForRegistration(
                isManualRequest: true,
                allowSettingsFallback: true
            )
            let autoEnabled = coordinator.handlePermissionReadiness(outcome.snapshot)
            if PermissionRequestFollowUpPlanner.shouldAttemptListeningRestart(
                openedSettingsFallback: outcome.openedSettingsFallback,
                autoEnabled: autoEnabled,
                listeningEnabled: coordinator.settings.listeningEnabled,
                globalStopActive: coordinator.globalStopActive
            ) {
                coordinator.startListening(showFailureHUD: true)
            }
            coordinator.rebuildMenu()
            coordinator.applyPendingConfigHotReloadIfNeeded()
        }
    }

    func requestInputMonitoringPermission() {
        PermissionChecker.requestInputMonitoringPrompt()
        restartListeningAfterPermissionChange(autoEnabled: coordinator.handlePermissionReadiness(PermissionChecker.snapshot()))
        coordinator.rebuildMenu()
    }

    func requestSpeechRecognitionPermission() {
        Task {
            _ = await PermissionChecker.requestSpeechRecognition()
            restartListeningAfterPermissionChange(autoEnabled: coordinator.handlePermissionReadiness(PermissionChecker.snapshot()))
            coordinator.rebuildMenu()
        }
    }

    func runStartupPermissionGuideIfNeeded() async {
        await runPermissionGuide(isManualRequest: false)
    }

    func runPermissionGuide(isManualRequest: Bool) async {
        let snapshot = PermissionChecker.snapshot()
        let currentIdentity = PermissionInstallIdentity.current()
        let runState = PermissionGuideRunState(
            didRunStartupGuide: coordinator.settings.didRunStartupPermissionGuide,
            storedIdentity: coordinator.settings.startupPermissionGuideIdentity,
            currentIdentity: currentIdentity
        )
        let actions = PermissionGuidePlanner.actions(
            for: snapshot,
            hasRunStartupGuide: runState.hasRunForCurrentIdentity,
            isManualRequest: isManualRequest,
            requiresSpeechRecognition: coordinator.settings.pipelineMode.usesSystemASR
        )
        guard !actions.isEmpty else {
            let autoEnabled = coordinator.handlePermissionReadiness(snapshot)
            if !autoEnabled, coordinator.stopReason == .permissionBlocked {
                coordinator.schedulePermissionReadinessPollingIfNeeded()
            }
            if autoEnabled || isManualRequest {
                coordinator.rebuildMenu()
            }
            return
        }

        coordinator.settings.didRunStartupPermissionGuide = true
        coordinator.settings.startupPermissionGuideIdentity = currentIdentity
        if actions.contains(.requestMicrophone) {
            _ = await PermissionChecker.requestMicrophone()
        }
        if actions.contains(.requestAccessibility) {
            let accessibilityOutcome = await requestAccessibilityPermissionAndWaitForRegistration(
                isManualRequest: isManualRequest,
                allowSettingsFallback: actions.contains(.openAccessibilitySettings)
            )
            let accessibilitySnapshot = accessibilityOutcome.snapshot
            if actions.contains(.openAccessibilitySettings), !accessibilitySnapshot.accessibilityGranted {
                let autoEnabled = coordinator.handlePermissionReadiness(accessibilitySnapshot)
                if PermissionRequestFollowUpPlanner.shouldAttemptListeningRestart(
                    openedSettingsFallback: accessibilityOutcome.openedSettingsFallback,
                    autoEnabled: autoEnabled,
                    listeningEnabled: coordinator.settings.listeningEnabled,
                    globalStopActive: coordinator.globalStopActive
                ) {
                    coordinator.startListening(showFailureHUD: isManualRequest)
                }
                if !PermissionRequestFollowUpPlanner.shouldContinueGuideAfterAccessibilityFallback(
                    openedSettingsFallback: accessibilityOutcome.openedSettingsFallback,
                    isManualRequest: isManualRequest
                ) {
                    coordinator.rebuildMenu()
                    return
                }
                coordinator.rebuildMenu()
                return
            }
        }
        if actions.contains(.requestInputMonitoring) {
            PermissionChecker.requestInputMonitoringPrompt()
        }
        if actions.contains(.requestSpeechRecognition) {
            _ = await PermissionChecker.requestSpeechRecognition()
        }

        try? await Task.sleep(nanoseconds: coordinator.permissionRequestSettleDelay)
        let updated = PermissionChecker.snapshot()
        if actions.contains(.openInputMonitoringSettings), !updated.inputMonitoringGranted {
            coordinator.tapStatus = coordinator.strings.listeningUnavailable()
            if isManualRequest {
                coordinator.hud.showWarningStatus(coordinator.strings.inputMonitoringManual, duration: coordinator.warningDuration)
            }
            PermissionChecker.openInputMonitoringSettings()
        }
        let autoEnabled = coordinator.handlePermissionReadiness(updated)
        if PermissionRequestFollowUpPlanner.shouldAttemptListeningRestart(
            openedSettingsFallback: false,
            autoEnabled: autoEnabled,
            listeningEnabled: coordinator.settings.listeningEnabled,
            globalStopActive: coordinator.globalStopActive
        ) {
            coordinator.startListening(showFailureHUD: isManualRequest)
        }
        coordinator.rebuildMenu()
    }

    func requestAccessibilityPermissionAndWaitForRegistration(
        isManualRequest: Bool,
        allowSettingsFallback: Bool
    ) async -> AccessibilityPermissionRequestOutcome {
        PermissionChecker.requestAccessibilityPrompt()
        try? await Task.sleep(nanoseconds: allowSettingsFallback ? coordinator.accessibilityPromptFallbackDelay : coordinator.permissionRequestSettleDelay)
        let snapshot = PermissionChecker.snapshot()
        var openedSettingsFallback = false
        if allowSettingsFallback, !snapshot.accessibilityGranted {
            coordinator.tapStatus = coordinator.strings.listeningUnavailable()
            if isManualRequest {
                coordinator.hud.showWarningStatus(coordinator.strings.accessibilityManual, duration: coordinator.permissionGuidanceDuration)
            }
            openedSettingsFallback = true
            PermissionChecker.openAccessibilitySettings()
        }
        return AccessibilityPermissionRequestOutcome(snapshot: snapshot, openedSettingsFallback: openedSettingsFallback)
    }

    private func restartListeningAfterPermissionChange(autoEnabled: Bool) {
        if !autoEnabled, coordinator.settings.listeningEnabled, !coordinator.globalStopActive {
            coordinator.startListening(showFailureHUD: true)
        }
    }
}
