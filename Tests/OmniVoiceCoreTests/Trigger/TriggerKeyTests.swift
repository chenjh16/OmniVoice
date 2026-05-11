import Foundation
import ApplicationServices
import Testing
@testable import OmniVoiceCore

@Suite("Trigger keys")
struct TriggerKeyTests {
    @Test
    func triggerCandidateWhitelist() {
        let candidates = TriggerKey.allCandidates
        #expect(candidates.first == .fnGlobe)
        #expect(TriggerKey.defaultTrigger == .fnGlobe)
        #expect(TriggerKey.candidate(identifier: nil) == .fnGlobe)
        #expect(candidates.contains(.capsLock))
        #expect(candidates.contains(.leftControl))
        #expect(TriggerKey.functionKeys.count == 12)
        #expect(TriggerKey.modifierKeys.count == 8)
        #expect(!candidates.contains { $0.keyCode == 53 })
        #expect(!candidates.contains { $0.displayLabel == "A" || $0.displayLabel == "1" })
        #expect(TriggerKey.captureCandidate(keyCode: 53) == nil)
        #expect(TriggerKey.captureCandidate(keyCode: 0) == nil)
        #expect(TriggerKey.captureCandidate(keyCode: 111)?.identifier == "function-f12")
        #expect(TriggerKey.captureCandidate(keyCode: 80) == nil)
        #expect(TriggerKey.candidate(identifier: "fallback-f19") == .fnGlobe)
        #expect(TriggerKey.captureCandidate(keyCode: 59) == .leftControl)
        #expect(TriggerKey.captureCandidate(keyCode: nil, includesFunctionModifier: true) == .fnGlobe)
    }
    @Test
    func configDefaultTriggerIsFnGlobe() {
        let preferences = ConfigPreferences.defaultPreferences(selectedModel: .defaultInputAudioModel)
        #expect(preferences.triggerKey == .fnGlobe)
    }

    @Test
    func continuousRecordingDoubleTapSupportIsStableFirst() {
        #expect(ContinuousRecordingTriggerSupportResolver.supportsDoubleTap(.fnGlobe))
        #expect(ContinuousRecordingTriggerSupportResolver.supportsDoubleTap(TriggerKey.functionKeys[0]))
        #expect(ContinuousRecordingTriggerSupportResolver.supportsDoubleTap(.leftControl))
        #expect(!ContinuousRecordingTriggerSupportResolver.supportsDoubleTap(.capsLock))
        #expect(ContinuousRecordingTapPlanner.isShortTap(duration: 0.29))
        #expect(!ContinuousRecordingTapPlanner.isShortTap(duration: 0.31))
        #expect(ContinuousRecordingTapPlanner.doubleTapInterval(systemInterval: 0.1) == 0.25)
        #expect(ContinuousRecordingTapPlanner.doubleTapInterval(systemInterval: 0.5) == 0.5)
        #expect(ContinuousRecordingTapPlanner.doubleTapInterval(systemInterval: 0.9) == 0.6)
    }

    @Test
    func continuousRecordingStopWaitsForReleaseBeforeFinishing() {
        #expect(ContinuousRecordingStopPlanner.actionForTriggerDown(
            active: true,
            stopPending: false
        ) == .waitForRelease)
        #expect(ContinuousRecordingStopPlanner.actionForTriggerDown(
            active: true,
            stopPending: true
        ) == .ignore)
        #expect(ContinuousRecordingStopPlanner.actionForTriggerDown(
            active: false,
            stopPending: false
        ) == .ignore)
        #expect(ContinuousRecordingStopPlanner.actionForTriggerUp(stopPending: true) == .finishAfterRelease)
        #expect(ContinuousRecordingStopPlanner.actionForTriggerUp(stopPending: false) == .ignore)
        #expect(ContinuousRecordingStopPlanner.actionForReleaseFallback(stopPending: true) == .finishAfterClearingTrigger)
        #expect(ContinuousRecordingStopPlanner.actionForReleaseFallback(stopPending: false) == .ignore)
        #expect(ContinuousRecordingStopPlanner.releaseFallbackInterval > 0.45)
    }

    @Test
    func continuousRecordingStateMachineCoversDoubleTapAndStopRelease() {
        var machine = ContinuousRecordingStateMachine()

        #expect(machine.triggerDown(doubleTapEnabled: true, appIsRecording: false) == .beginRecording)
        #expect(machine.triggerUp(
            doubleTapEnabled: true,
            appIsRecording: true,
            tapDuration: 0.12
        ) == .scheduleSecondTapWindow)
        #expect(machine.state.tapPending)

        #expect(machine.triggerDown(doubleTapEnabled: true, appIsRecording: true) == .enterContinuousRecording)
        #expect(machine.state.active)
        #expect(!machine.state.tapPending)
        #expect(machine.state.ignoreNextUp)

        #expect(machine.triggerUp(
            doubleTapEnabled: true,
            appIsRecording: true,
            tapDuration: 0.02
        ) == .ignoreTriggerUp)
        #expect(!machine.state.ignoreNextUp)

        #expect(machine.triggerDown(doubleTapEnabled: true, appIsRecording: true) == .beginStopTap)
        #expect(machine.state.stopPending)
        #expect(!machine.state.active)

        #expect(machine.triggerUp(
            doubleTapEnabled: true,
            appIsRecording: true,
            tapDuration: 12.0
        ) == .finishStopTap(clearTriggerState: false))
        #expect(!machine.state.stopPending)
    }

    @Test
    func continuousRecordingStateMachineHandlesTimeoutFallbackAndReset() {
        var timeoutMachine = ContinuousRecordingStateMachine()
        #expect(timeoutMachine.triggerDown(doubleTapEnabled: true, appIsRecording: false) == .beginRecording)
        #expect(timeoutMachine.triggerUp(
            doubleTapEnabled: true,
            appIsRecording: true,
            tapDuration: 0.1
        ) == .scheduleSecondTapWindow)
        #expect(timeoutMachine.secondTapTimeout() == .finishRecording)
        #expect(!timeoutMachine.state.tapPending)
        #expect(timeoutMachine.secondTapTimeout() == .ignore)

        var fallbackMachine = ContinuousRecordingStateMachine()
        #expect(fallbackMachine.triggerDown(doubleTapEnabled: true, appIsRecording: false) == .beginRecording)
        #expect(fallbackMachine.triggerUp(
            doubleTapEnabled: true,
            appIsRecording: true,
            tapDuration: 0.1
        ) == .scheduleSecondTapWindow)
        #expect(fallbackMachine.triggerDown(doubleTapEnabled: true, appIsRecording: true) == .enterContinuousRecording)
        #expect(fallbackMachine.triggerUp(
            doubleTapEnabled: true,
            appIsRecording: true,
            tapDuration: 0.01
        ) == .ignoreTriggerUp)
        #expect(fallbackMachine.triggerDown(doubleTapEnabled: true, appIsRecording: true) == .beginStopTap)
        #expect(fallbackMachine.triggerDown(doubleTapEnabled: true, appIsRecording: true) == .ignoreStopPending)
        #expect(fallbackMachine.stopReleaseFallback() == .finishStopTap(clearTriggerState: true))
        #expect(!fallbackMachine.state.stopPending)
        #expect(fallbackMachine.stopReleaseFallback() == .ignore)

        var resetMachine = ContinuousRecordingStateMachine()
        #expect(resetMachine.triggerDown(doubleTapEnabled: true, appIsRecording: false) == .beginRecording)
        #expect(resetMachine.triggerUp(
            doubleTapEnabled: true,
            appIsRecording: true,
            tapDuration: 0.1
        ) == .scheduleSecondTapWindow)
        #expect(resetMachine.triggerDown(doubleTapEnabled: true, appIsRecording: true) == .enterContinuousRecording)
        resetMachine.reset(preserveIgnoredUp: true)
        #expect(resetMachine.state.ignoreNextUp)
        #expect(resetMachine.triggerUp(
            doubleTapEnabled: true,
            appIsRecording: false,
            tapDuration: nil
        ) == .ignoreTriggerUp)
        #expect(!resetMachine.state.ignoreNextUp)
    }

    @Test
    func triggerCapturePlannerAcceptsOnlyWhitelistedKeys() {
        #expect(TriggerCapturePlanner.decide(
            kind: .flagsChanged,
            keyCode: nil,
            includesFunctionModifier: true
        ) == .capture(.fnGlobe))
        #expect(TriggerCapturePlanner.decide(kind: .keyDown, keyCode: 111) == .capture(TriggerKey.functionKeys[11]))
        #expect(TriggerCapturePlanner.decide(kind: .keyDown, keyCode: 105) == .reject)
        #expect(TriggerCapturePlanner.decide(kind: .keyDown, keyCode: 90) == .reject)
        #expect(TriggerCapturePlanner.decide(kind: .flagsChanged, keyCode: 62) == .capture(
            TriggerKey.modifierKeys.first { $0.identifier == "modifier-right-control" }!
        ))
        #expect(TriggerCapturePlanner.decide(kind: .flagsChanged, keyCode: 57) == .capture(.capsLock))
        #expect(TriggerCapturePlanner.decide(kind: .keyDown, keyCode: 53) == .cancel)
        #expect(TriggerCapturePlanner.decide(kind: .keyDown, keyCode: 0) == .reject)
        #expect(TriggerCapturePlanner.decide(kind: .keyDown, keyCode: 18) == .reject)
        #expect(TriggerCapturePlanner.decide(kind: .keyDown, keyCode: 105, isRepeat: true) == .ignore)
    }
    @Test
    func triggerPollingRecoveryDoesNotSynthesizeFnReleaseFromUnstableFlags() {
        #expect(!EventTapPollingRecoveryDecision.isReleaseCandidate(
            trigger: .fnGlobe,
            flags: []
        ))
        #expect(!EventTapPollingRecoveryDecision.isReleaseCandidate(
            trigger: .leftControl,
            flags: [.maskControl]
        ))
        #expect(EventTapPollingRecoveryDecision.isReleaseCandidate(
            trigger: .leftControl,
            flags: []
        ))
        #expect(!EventTapPollingRecoveryDecision.isReleaseCandidate(trigger: .capsLock, flags: []))
        let start = Date()
        #expect(!EventTapPollingRecoveryDecision.shouldPostSyntheticUp(
            candidateSince: start,
            now: start.addingTimeInterval(0.5),
            graceSeconds: 0.75
        ))
        #expect(EventTapPollingRecoveryDecision.shouldPostSyntheticUp(
            candidateSince: start,
            now: start.addingTimeInterval(0.8),
            graceSeconds: 0.75
        ))
    }
    @Test
    func fnTriggerDoesNotSuppressUnrelatedModifierChanges() {
        #expect(EventTapTriggerClassifier.decision(
            for: .fnGlobe,
            type: .flagsChanged,
            flags: [.maskAlternate],
            keyCode: 58,
            isRepeat: false,
            triggerPressed: false
        ) == .passThrough)
        #expect(EventTapTriggerClassifier.decision(
            for: .fnGlobe,
            type: .flagsChanged,
            flags: [.maskSecondaryFn],
            keyCode: 63,
            isRepeat: false,
            triggerPressed: false
        ) == EventTapTriggerDecision(action: .down, shouldSuppress: true))
        #expect(EventTapTriggerClassifier.decision(
            for: .fnGlobe,
            type: .flagsChanged,
            flags: [.maskAlternate],
            keyCode: 63,
            isRepeat: false,
            triggerPressed: true
        ) == EventTapTriggerDecision(action: .up, shouldSuppress: true))
        #expect(EventTapTriggerClassifier.decision(
            for: .fnGlobe,
            type: .flagsChanged,
            flags: [.maskSecondaryFn, .maskAlternate],
            keyCode: 58,
            isRepeat: false,
            triggerPressed: true
        ) == .passThrough)
    }
    @Test
    func fnTriggerCancelsRecordingWhenCombinedWithAnotherKey() {
        #expect(EventTapFnCombinationCancellation.cancelReason(
            trigger: .fnGlobe,
            type: .keyDown,
            triggerPressed: true
        ) == .triggerCombination)
        #expect(EventTapFnCombinationCancellation.cancelReason(
            trigger: .fnGlobe,
            type: EventTapEventTypes.systemDefined,
            triggerPressed: true
        ) == .triggerCombination)
        #expect(EventTapFnCombinationCancellation.shouldCancel(
            trigger: .fnGlobe,
            type: .keyDown,
            triggerPressed: true
        ))
        #expect(EventTapFnCombinationCancellation.shouldCancel(
            trigger: .fnGlobe,
            type: EventTapEventTypes.systemDefined,
            triggerPressed: true
        ))
        #expect(!EventTapFnCombinationCancellation.shouldCancel(
            trigger: .fnGlobe,
            type: .flagsChanged,
            triggerPressed: true
        ))
        #expect(!EventTapFnCombinationCancellation.shouldCancel(
            trigger: .fnGlobe,
            type: .keyDown,
            triggerPressed: false
        ))
        #expect(!EventTapFnCombinationCancellation.shouldCancel(
            trigger: .leftControl,
            type: .keyDown,
            triggerPressed: true
        ))
    }

    @Test
    func escapeCancellationRequiresActiveCancellationMode() {
        #expect(EventTapEscapeCancellation.cancelReason(
            type: .keyDown,
            keyCode: FnEscapeRescueDetector.escapeKeyCode,
            cancellationActive: true
        ) == .escapeKey)
        #expect(EventTapEscapeCancellation.cancelReason(
            type: .keyDown,
            keyCode: FnEscapeRescueDetector.escapeKeyCode,
            cancellationActive: false
        ) == nil)
        #expect(EventTapEscapeCancellation.cancelReason(
            type: .keyUp,
            keyCode: FnEscapeRescueDetector.escapeKeyCode,
            cancellationActive: true
        ) == nil)
    }

    @Test
    func fnEscapeTriggersEmergencyRescue() {
        #expect(FnEscapeRescueDetector.shouldRescue(
            type: .keyDown,
            keyCode: FnEscapeRescueDetector.escapeKeyCode,
            flags: [.maskSecondaryFn]
        ))
    }
    @Test
    func plainEscapeDoesNotTriggerEmergencyRescue() {
        #expect(!FnEscapeRescueDetector.shouldRescue(
            type: .keyDown,
            keyCode: FnEscapeRescueDetector.escapeKeyCode,
            flags: []
        ))
    }
    @Test
    func fnSystemKeyDoesNotTriggerEmergencyRescue() {
        #expect(!FnEscapeRescueDetector.shouldRescue(
            type: EventTapEventTypes.systemDefined,
            keyCode: FnEscapeRescueDetector.escapeKeyCode,
            flags: [.maskSecondaryFn]
        ))
        #expect(!FnEscapeRescueDetector.shouldRescue(
            type: .keyDown,
            keyCode: 122,
            flags: [.maskSecondaryFn]
        ))
    }
    @Test
    func triggerCaptureSessionPlannerPausesAndRestoresNormalTap() {
        #expect(TriggerCaptureSessionPlanner.begin(
            listeningEnabled: true,
            normalTapRunning: true
        ).shouldPauseNormalTap)
        #expect(!TriggerCaptureSessionPlanner.begin(
            listeningEnabled: true,
            normalTapRunning: false
        ).shouldPauseNormalTap)
        #expect(TriggerCaptureSessionPlanner.finish(
            pausedNormalTap: true,
            restartListening: true,
            listeningEnabled: true
        ).shouldRestoreNormalTap)
        #expect(!TriggerCaptureSessionPlanner.finish(
            pausedNormalTap: true,
            restartListening: false,
            listeningEnabled: true
        ).shouldRestoreNormalTap)
        #expect(!TriggerCaptureSessionPlanner.finish(
            pausedNormalTap: true,
            restartListening: true,
            listeningEnabled: false
        ).shouldRestoreNormalTap)
    }
    @Test
    func eventTapWatchdogResetsOnlyAfterTimeout() {
        let pressedAt = Date(timeIntervalSince1970: 100)
        #expect(!EventTapWatchdogDecision.shouldReset(
            pressedAt: nil,
            now: Date(timeIntervalSince1970: 500),
            timeoutSeconds: 10
        ))
        #expect(!EventTapWatchdogDecision.shouldReset(
            pressedAt: pressedAt,
            now: Date(timeIntervalSince1970: 109),
            timeoutSeconds: 10
        ))
        #expect(EventTapWatchdogDecision.shouldReset(
            pressedAt: pressedAt,
            now: Date(timeIntervalSince1970: 110),
            timeoutSeconds: 10
        ))
    }
}
