import AppKit
import Foundation

extension AppCoordinator {
    func handleRecordingTriggerDown() {
        let action = continuousRecordingRuntime.stateMachine.triggerDown(
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
            continuousRecordingRuntime.tapTimeout.cancel()
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
        let action = continuousRecordingRuntime.stateMachine.triggerUp(
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
        continuousRecordingRuntime.stopFallback.schedule(
            after: ContinuousRecordingStopPlanner.releaseFallbackInterval
        ) { [weak self] in
            self?.expireContinuousRecordingStopTap()
        }
    }

    func finishContinuousRecordingStopTap(clearTriggerState: Bool) {
        continuousRecordingRuntime.stopFallback.cancel()
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
        switch continuousRecordingRuntime.stateMachine.stopReleaseFallback() {
        case let .finishStopTap(clearTriggerState):
            finishContinuousRecordingStopTap(clearTriggerState: clearTriggerState)
        case .finishRecording:
            finishRecordingAndTranscribe()
        case .ignore:
            break
        }
    }

    func scheduleContinuousRecordingSecondTapWindow(firstTapDuration: TimeInterval) {
        continuousRecordingRuntime.tapTimeout.cancel()
        let interval = continuousRecordingDoubleTapInterval
        recordLocalDiagnostic(
            stage: "continuous_recording_first_tap_pending",
            details: [
                "trigger": settings.triggerKey.identifier,
                "first_tap_seconds": String(format: "%.3f", firstTapDuration),
                "double_tap_interval_seconds": String(format: "%.3f", interval)
            ]
        )
        continuousRecordingRuntime.tapTimeout.schedule(after: interval) { [weak self] in
            self?.expireContinuousRecordingSecondTapWindow()
        }
    }

    func expireContinuousRecordingSecondTapWindow() {
        continuousRecordingRuntime.tapTimeout.cancel()
        switch continuousRecordingRuntime.stateMachine.secondTapTimeout() {
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
        continuousRecordingRuntime.cancelTimers()
        continuousRecordingRuntime.stateMachine.reset(preserveIgnoredUp: preserveIgnoredUp)
    }
}
