import Foundation
import ApplicationServices
import Testing
@testable import OmniVoiceCore
@testable import OmniVoiceE2ESupport

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
    func settingsDefaultTriggerIsFnGlobe() {
        let suiteName = "omnivoice-default-trigger-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        #expect(settings.triggerKey == .fnGlobe)
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
