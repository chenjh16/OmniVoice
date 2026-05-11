import Foundation

extension AppCoordinator {
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
        performCriticalRuntimeStop(.triggerAckTimeout)
    }

    func performEmergencyRescueExit() {
        performCriticalRuntimeStop(.emergencyRescueExit)
    }
}
