import Foundation

public enum ContinuousRecordingTapPlanner {
    public static let tapMaxDuration: TimeInterval = 0.30

    public static func doubleTapInterval(systemInterval: TimeInterval) -> TimeInterval {
        min(max(systemInterval, 0.25), 0.60)
    }

    public static func isShortTap(duration: TimeInterval) -> Bool {
        duration <= tapMaxDuration
    }
}

public enum ContinuousRecordingStopAction: Equatable, Sendable {
    case ignore
    case waitForRelease
    case finishAfterRelease
    case finishAfterClearingTrigger
}

public enum ContinuousRecordingStopPlanner {
    public static let releaseFallbackInterval: TimeInterval = 0.85

    public static func actionForTriggerDown(active: Bool, stopPending: Bool) -> ContinuousRecordingStopAction {
        guard active, !stopPending else { return .ignore }
        return .waitForRelease
    }

    public static func actionForTriggerUp(stopPending: Bool) -> ContinuousRecordingStopAction {
        stopPending ? .finishAfterRelease : .ignore
    }

    public static func actionForReleaseFallback(stopPending: Bool) -> ContinuousRecordingStopAction {
        stopPending ? .finishAfterClearingTrigger : .ignore
    }
}

public struct ContinuousRecordingStateMachine: Equatable, Sendable {
    public struct State: Equatable, Sendable {
        public var tapPending: Bool
        public var active: Bool
        public var ignoreNextUp: Bool
        public var stopPending: Bool

        public static let idle = State(
            tapPending: false,
            active: false,
            ignoreNextUp: false,
            stopPending: false
        )
    }

    public enum TriggerDownAction: Equatable, Sendable {
        case beginRecording
        case beginStopTap
        case enterContinuousRecording
        case ignoreStopPending
    }

    public enum TriggerUpAction: Equatable, Sendable {
        case finishRecording
        case finishStopTap(clearTriggerState: Bool)
        case scheduleSecondTapWindow
        case ignoreTriggerUp
    }

    public enum TimeoutAction: Equatable, Sendable {
        case finishRecording
        case finishStopTap(clearTriggerState: Bool)
        case ignore
    }

    public private(set) var state: State

    public init(state: State = .idle) {
        self.state = state
    }

    public mutating func triggerDown(doubleTapEnabled: Bool, appIsRecording: Bool) -> TriggerDownAction {
        guard doubleTapEnabled else {
            reset()
            return .beginRecording
        }

        if state.stopPending {
            return .ignoreStopPending
        }

        switch ContinuousRecordingStopPlanner.actionForTriggerDown(
            active: state.active,
            stopPending: state.stopPending
        ) {
        case .waitForRelease:
            state.active = false
            state.ignoreNextUp = false
            state.stopPending = true
            return .beginStopTap
        case .ignore, .finishAfterRelease, .finishAfterClearingTrigger:
            break
        }

        if state.tapPending, appIsRecording {
            state.tapPending = false
            state.active = true
            state.ignoreNextUp = true
            return .enterContinuousRecording
        }

        state.tapPending = false
        return .beginRecording
    }

    public mutating func triggerUp(
        doubleTapEnabled: Bool,
        appIsRecording: Bool,
        tapDuration: TimeInterval?
    ) -> TriggerUpAction {
        switch ContinuousRecordingStopPlanner.actionForTriggerUp(stopPending: state.stopPending) {
        case .finishAfterRelease:
            state.stopPending = false
            return .finishStopTap(clearTriggerState: false)
        case .ignore, .waitForRelease, .finishAfterClearingTrigger:
            break
        }

        if state.ignoreNextUp {
            state.ignoreNextUp = false
            return .ignoreTriggerUp
        }

        guard doubleTapEnabled else {
            reset()
            return .finishRecording
        }

        if state.active {
            return .ignoreTriggerUp
        }

        guard appIsRecording, let tapDuration else {
            return .finishRecording
        }

        guard ContinuousRecordingTapPlanner.isShortTap(duration: tapDuration) else {
            return .finishRecording
        }

        state.tapPending = true
        return .scheduleSecondTapWindow
    }

    public mutating func secondTapTimeout() -> TimeoutAction {
        guard state.tapPending else { return .ignore }
        state.tapPending = false
        return .finishRecording
    }

    public mutating func stopReleaseFallback() -> TimeoutAction {
        switch ContinuousRecordingStopPlanner.actionForReleaseFallback(stopPending: state.stopPending) {
        case .finishAfterClearingTrigger:
            state.stopPending = false
            return .finishStopTap(clearTriggerState: true)
        case .ignore, .waitForRelease, .finishAfterRelease:
            return .ignore
        }
    }

    public mutating func reset(preserveIgnoredUp: Bool = false) {
        let shouldPreserveIgnoredUp = preserveIgnoredUp && state.ignoreNextUp
        state = .idle
        state.ignoreNextUp = shouldPreserveIgnoredUp
    }
}

public enum ContinuousRecordingTriggerSupportResolver {
    public static func supportsDoubleTap(_ trigger: TriggerKey) -> Bool {
        switch trigger.kind {
        case .fnGlobe, .functionKey, .modifier:
            return true
        case .capsLock:
            return false
        }
    }
}
