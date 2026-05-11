import AppKit
import Foundation

extension AppCoordinator {
    func handleRecordingTriggerDown() {
        let action = continuousRecordingStateMachine.triggerDown(
            doubleTapEnabled: shouldUseContinuousRecordingDoubleTap,
            appIsRecording: state == .recording
        )

        switch action {
        case .beginRecording:
            beginRecording()
        case .ignoreStopPending:
            recordLocalDiagnostic(
                stage: "continuous_recording_stop_tap_ignored",
                details: ["trigger": settings.triggerKey.identifier]
            )
        case .beginStopTap:
            beginContinuousRecordingStopTap()
        case .enterContinuousRecording:
            continuousRecordingTapTimeout?.cancel()
            continuousRecordingTapTimeout = nil
            recordLocalDiagnostic(
                stage: "continuous_recording_started",
                details: [
                    "trigger": settings.triggerKey.identifier,
                    "double_tap_interval_seconds": String(format: "%.3f", continuousRecordingDoubleTapInterval)
                ]
            )
        }
    }

    func handleRecordingTriggerUp() {
        let tapDuration = recordingStartDate.map { Date().timeIntervalSince($0) }
        let action = continuousRecordingStateMachine.triggerUp(
            doubleTapEnabled: shouldUseContinuousRecordingDoubleTap,
            appIsRecording: state == .recording,
            tapDuration: tapDuration
        )

        switch action {
        case .finishRecording:
            finishRecordingAndTranscribe()
        case let .finishStopTap(clearTriggerState):
            finishContinuousRecordingStopTap(clearTriggerState: clearTriggerState)
        case .scheduleSecondTapWindow:
            scheduleContinuousRecordingSecondTapWindow(firstTapDuration: tapDuration ?? 0)
        case .ignoreTriggerUp:
            recordLocalDiagnostic(
                stage: "continuous_recording_trigger_up_ignored",
                details: ["trigger": settings.triggerKey.identifier]
            )
        }
    }

    func beginContinuousRecordingStopTap() {
        scheduleContinuousRecordingStopFallback()
        recordLocalDiagnostic(
            stage: "continuous_recording_stop_tap",
            details: ["trigger": settings.triggerKey.identifier]
        )
    }

    func scheduleContinuousRecordingStopFallback() {
        continuousRecordingStopFallback?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.expireContinuousRecordingStopTap()
            }
        }
        continuousRecordingStopFallback = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + ContinuousRecordingStopPlanner.releaseFallbackInterval,
            execute: workItem
        )
    }

    func finishContinuousRecordingStopTap(clearTriggerState: Bool) {
        continuousRecordingStopFallback?.cancel()
        continuousRecordingStopFallback = nil
        if clearTriggerState {
            eventTap.clearCurrentTriggerStateForContinuousRecording()
        }
        recordLocalDiagnostic(
            stage: clearTriggerState ? "continuous_recording_stop_release_fallback" : "continuous_recording_stop_release",
            details: ["trigger": settings.triggerKey.identifier]
        )
        finishRecordingAndTranscribe()
    }

    func expireContinuousRecordingStopTap() {
        switch continuousRecordingStateMachine.stopReleaseFallback() {
        case let .finishStopTap(clearTriggerState):
            finishContinuousRecordingStopTap(clearTriggerState: clearTriggerState)
        case .finishRecording:
            finishRecordingAndTranscribe()
        case .ignore:
            break
        }
    }

    func scheduleContinuousRecordingSecondTapWindow(firstTapDuration: TimeInterval) {
        continuousRecordingTapTimeout?.cancel()
        let interval = continuousRecordingDoubleTapInterval
        recordLocalDiagnostic(
            stage: "continuous_recording_first_tap_pending",
            details: [
                "trigger": settings.triggerKey.identifier,
                "first_tap_seconds": String(format: "%.3f", firstTapDuration),
                "double_tap_interval_seconds": String(format: "%.3f", interval)
            ]
        )
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.expireContinuousRecordingSecondTapWindow()
            }
        }
        continuousRecordingTapTimeout = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
    }

    func expireContinuousRecordingSecondTapWindow() {
        continuousRecordingTapTimeout = nil
        switch continuousRecordingStateMachine.secondTapTimeout() {
        case .finishRecording:
            recordLocalDiagnostic(
                stage: "continuous_recording_second_tap_timeout",
                details: ["trigger": settings.triggerKey.identifier]
            )
            finishRecordingAndTranscribe()
        case let .finishStopTap(clearTriggerState):
            finishContinuousRecordingStopTap(clearTriggerState: clearTriggerState)
        case .ignore:
            break
        }
    }

    func resetContinuousRecordingTriggerState(preserveIgnoredUp: Bool = false) {
        continuousRecordingTapTimeout?.cancel()
        continuousRecordingTapTimeout = nil
        continuousRecordingStopFallback?.cancel()
        continuousRecordingStopFallback = nil
        continuousRecordingStateMachine.reset(preserveIgnoredUp: preserveIgnoredUp)
    }
}
