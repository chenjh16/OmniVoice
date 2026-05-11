import CoreGraphics
import Foundation

public enum EventTapPollingRecoveryDecision {
    public static func isReleaseCandidate(trigger: TriggerKey, flags: CGEventFlags) -> Bool {
        switch trigger.kind {
        case .fnGlobe:
            return false
        case .modifier:
            return flags.rawValue & trigger.modifierFlagsRawValue == 0
        case .functionKey, .capsLock:
            return false
        }
    }

    public static func shouldPostSyntheticUp(
        candidateSince: Date,
        now: Date,
        graceSeconds: TimeInterval
    ) -> Bool {
        now.timeIntervalSince(candidateSince) >= graceSeconds
    }
}

public enum EventTapWatchdogDecision {
    public static func shouldReset(
        pressedAt: Date?,
        now: Date,
        timeoutSeconds: TimeInterval
    ) -> Bool {
        guard let pressedAt else { return false }
        return now.timeIntervalSince(pressedAt) >= timeoutSeconds
    }
}
