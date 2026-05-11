import AppKit
import Foundation

struct CriticalRuntimeStopOptions {
    let stage: String
    let errorKind: String
    let stopTriggerCapture: Bool
    let stopPermissionReadinessPolling: Bool
    let clearRuntimeActive: Bool
    let terminateApp: Bool
}

extension CriticalRuntimeStopOptions {
    static let triggerAckTimeout = CriticalRuntimeStopOptions(
        stage: "event_tap_trigger_ack_timeout",
        errorKind: "trigger_ack_timeout",
        stopTriggerCapture: false,
        stopPermissionReadinessPolling: false,
        clearRuntimeActive: false,
        terminateApp: false
    )

    static let emergencyRescueExit = CriticalRuntimeStopOptions(
        stage: "fn_escape_quit",
        errorKind: "emergency_rescue",
        stopTriggerCapture: true,
        stopPermissionReadinessPolling: true,
        clearRuntimeActive: true,
        terminateApp: true
    )
}

extension AppCoordinator {
    func performCriticalRuntimeStop(_ options: CriticalRuntimeStopOptions) {
        resetContinuousRecordingTriggerState()
        recordingTimingRuntime.maxRecordingTimer.cancel()
        resetListeningHUDRevealState()
        let stopWasPending = cancelPendingRecordingStop()
        transcriptionTask?.cancel()
        pendingTranscription?.liveASRFinalTask?.cancel()
        transcriptionTask = nil
        if RecordingStopCancellationPlanner.shouldCancelRecordingSource(recordingStopInProgress: stopWasPending) {
            recordingSource.cancel()
        }
        cancelLiveASRSession()
        if options.stopTriggerCapture {
            triggerCapture.stop()
        }
        eventTap.setCancellationActive(false)
        eventTap.setTriggerSuppressionEnabled(false)
        eventTap.stop()
        hud.hide()
        actionPanel.cancel()
        recordingFocus = nil
        recordingStartDate = nil
        pendingTranscription = nil
        if options.stopPermissionReadinessPolling {
            stopPermissionReadinessPolling()
        }
        stopPermissionDriftMonitoring()
        state = .idle
        settings.listeningEnabled = false
        globalStopActive = true
        stopReason = .manual
        settings.stopReason = .manual
        if options.clearRuntimeActive {
            settings.runtimeActive = false
        }
        tapStatus = strings.stopped
        recordLocalDiagnostic(
            stage: options.stage,
            errorKind: options.errorKind,
            details: diagnosticRuntimeDetails(["listening_enabled": "false"])
        )
        if options.terminateApp {
            NSApp.terminate(nil)
        } else {
            rebuildMenu()
        }
    }
}
