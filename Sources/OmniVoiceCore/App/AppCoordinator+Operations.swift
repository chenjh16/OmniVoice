import AppKit
import Foundation

extension AppCoordinator {
    func cancelCurrentOperation(reason: EventTapCancellationReason = .escapeKey) {
        resetContinuousRecordingTriggerState()
        switch state {
        case .recording:
            let isSilent = reason == .triggerCombination
            recordingSource.cancel()
            cancelLiveASRSession()
            state = .idle
            eventTap.setCancellationActive(false)
            updateEventTapTriggerSuppression()
            maxRecordingTimer?.invalidate()
            maxRecordingTimer = nil
            resetListeningHUDRevealState()
            recordingFocus = nil
            recordingStartDate = nil
            pendingTranscription = nil
            actionPanel.cancel()
            if isSilent {
                hud.hide()
            } else {
                hud.showTransientStatus(strings.cancelled, duration: warningDuration)
            }
            recordLocalDiagnostic(
                stage: "recording_cancelled",
                errorKind: isSilent ? "trigger_combination_cancelled" : "cancelled",
                details: [
                    "reason": String(describing: reason),
                    "shown_to_user": isSilent ? "false" : "true"
                ]
            )
            completeAutomation(
                ok: false,
                pending: nil,
                injectionResult: nil,
                fallbackReason: nil,
                errorKind: isSilent ? "trigger_combination_cancelled" : "cancelled"
            )
        case .transcribing:
            let pending = pendingTranscription
            _ = cancelPendingRecordingStop()
            transcriptionTask?.cancel()
            pending?.liveASRFinalTask?.cancel()
            transcriptionTask = nil
            state = .idle
            eventTap.setCancellationActive(false)
            updateEventTapTriggerSuppression()
            recordingFocus = nil
            resetListeningHUDRevealState()
            pendingTranscription = nil
            actionPanel.cancel()
            hud.showTransientStatus(strings.cancelled, duration: warningDuration)
            completeAutomation(
                ok: false,
                pending: pending,
                injectionResult: nil,
                fallbackReason: nil,
                errorKind: "cancelled"
            )
        case .idle:
            actionPanel.cancel()
            break
        }
        rebuildMenu()
        applyPendingConfigHotReloadIfNeeded()
    }

    func refreshModels(showStatus: Bool) async {
        await refreshSourceLatencies(showStatus: false)
        if showStatus {
            hud.showTransientStatus(strings.modelsRefreshed, duration: warningDuration)
        }
        rebuildMenu()
    }

    func sanitizedMessage(for error: Error) -> String {
        let description = (error as? LocalizedError)?.errorDescription ?? "操作失败"
        if description.count > 90 {
            return String(description.prefix(90)) + "…"
        }
        return description
    }

    func diagnosticKind(for error: Error) -> String {
        if let audioError = error as? AudioRecorderError {
            return String(describing: audioError)
        }
        if let mimoError = error as? MimoAPIError {
            return mimoError.diagnosticKind
        }
        if let speechError = error as? SystemSpeechRecognitionError {
            return speechError.diagnosticKind
        }
        return String(describing: type(of: error))
    }

    func diagnosticHTTPStatus(for error: Error) -> String? {
        guard let mimoError = error as? MimoAPIError else { return nil }
        switch mimoError {
        case .httpStatus(let status, _):
            return String(status)
        case .modelDoesNotSupportText(let status, _):
            return status.map(String.init)
        default:
            return nil
        }
    }

    func recordingValidationStatus(for error: Error) -> RecordingValidationResult.Status? {
        guard let audioError = error as? AudioRecorderError else { return nil }
        switch audioError {
        case .tooShort:
            return .tooShort
        case .tooQuiet:
            return .tooQuiet
        case .alreadyRecording, .notRecording, .noInputFormat, .noSamples, .conversionFailed, .invalidWAV:
            return nil
        }
    }
}
