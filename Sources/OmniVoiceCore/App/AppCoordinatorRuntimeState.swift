import Foundation

@MainActor
final class RecordingSessionRuntimeState {
    var focus: FocusSnapshot?
    var startDate: Date?
    var pendingTranscription: PendingTranscription?

    func clearRecording() {
        focus = nil
        startDate = nil
    }

    func clearAll() {
        clearRecording()
        pendingTranscription = nil
    }
}

@MainActor
final class SourceLatencyRuntimeState {
    var results: [String: SourceLatencyMeasurement] = [:]
    let timer = MainActorTimerSlot()

    func invalidateTimer() {
        timer.cancel()
    }
}

@MainActor
final class RecordingReplayAutomationRuntimeState {
    var options: RecordingReplayAutomationOptions?
    var continuation: CheckedContinuation<RecordingReplayAutomationResult, Never>?
    var recordingResult: AudioRecordingResult?
    let guiFrameTimer = MainActorTimerSlot()
    var guiFrameIndex = 0
    var previousUILanguage: UILanguage?

    var isRunning: Bool {
        continuation != nil
    }

    func begin(
        options: RecordingReplayAutomationOptions,
        continuation: CheckedContinuation<RecordingReplayAutomationResult, Never>,
        previousUILanguage: UILanguage?
    ) {
        self.options = options
        self.continuation = continuation
        self.recordingResult = nil
        self.previousUILanguage = previousUILanguage
    }

    func clearSession() {
        continuation = nil
        options = nil
        recordingResult = nil
        previousUILanguage = nil
    }

    func resetGUIFrameCapture() {
        guiFrameIndex = 0
    }

    func invalidateGUIFrameTimer() {
        guiFrameTimer.cancel()
    }
}

@MainActor
final class RecordingTimingRuntimeState {
    let maxRecordingTimer = MainActorTimerSlot()
    let listeningHUDRevealTimer = MainActorTimerSlot()
    var listeningHUDShownForCurrentRecording = false
}

@MainActor
final class ContinuousRecordingRuntimeState {
    var stateMachine = ContinuousRecordingStateMachine()
    let tapTimeout = MainActorWorkItemSlot()
    let stopFallback = MainActorWorkItemSlot()

    func cancelTimers() {
        tapTimeout.cancel()
        stopFallback.cancel()
    }
}

@MainActor
final class PermissionPollingRuntimeState {
    let readinessTimer = MainActorTimerSlot()
    let driftTimer = MainActorTimerSlot()
}

@MainActor
final class TriggerCaptureRuntimeState {
    let timeoutTimer = MainActorTimerSlot()
    var pausedListening = false
    weak var view: TriggerCaptureMenuView?
}
