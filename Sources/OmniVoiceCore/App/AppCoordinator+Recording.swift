import AppKit
import Foundation

extension AppCoordinator {
    func beginRecording() {
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
            startLiveASRIfNeeded()
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
            resetContinuousRecordingTriggerState()
            cancelLiveASRSession()
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

}
