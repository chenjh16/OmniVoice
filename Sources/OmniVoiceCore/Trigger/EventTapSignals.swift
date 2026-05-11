import Foundation

public enum EventTapSignal: Equatable, Sendable {
    case triggerDown
    case triggerUp
    case cancel(EventTapCancellationReason)
    case tapDisabled
    case tapReenabled
    case tapFailed
    case triggerAckTimeout
    case triggerWatchdogReset
    case emergencyRescue
}

public enum EventTapCancellationReason: Equatable, Sendable {
    case escapeKey
    case triggerCombination
}
