import CoreGraphics
import Foundation

public enum EventTapTriggerAction: Equatable, Sendable {
    case down
    case up
}

public struct EventTapTriggerDecision: Equatable, Sendable {
    public let action: EventTapTriggerAction?
    public let shouldSuppress: Bool

    public init(action: EventTapTriggerAction?, shouldSuppress: Bool) {
        self.action = action
        self.shouldSuppress = shouldSuppress
    }

    public static let passThrough = EventTapTriggerDecision(action: nil, shouldSuppress: false)
}

public enum EventTapTriggerClassifier {
    public static func decision(
        for trigger: TriggerKey,
        type: CGEventType,
        flags: CGEventFlags,
        keyCode: Int,
        isRepeat: Bool,
        triggerPressed: Bool
    ) -> EventTapTriggerDecision {
        switch trigger.kind {
        case .fnGlobe:
            guard type == .flagsChanged else { return .passThrough }
            let fnDown = flags.contains(.maskSecondaryFn)
            guard fnDown != triggerPressed else { return .passThrough }
            return EventTapTriggerDecision(action: fnDown ? .down : .up, shouldSuppress: true)
        case .functionKey:
            guard trigger.keyCode == keyCode else { return .passThrough }
            if type == .keyDown {
                return EventTapTriggerDecision(action: isRepeat ? nil : .down, shouldSuppress: true)
            }
            if type == .keyUp {
                return EventTapTriggerDecision(action: .up, shouldSuppress: true)
            }
            return .passThrough
        case .modifier:
            guard type == .flagsChanged, trigger.keyCode == keyCode else { return .passThrough }
            let pressed = flags.rawValue & trigger.modifierFlagsRawValue != 0
            return EventTapTriggerDecision(action: pressed ? .down : .up, shouldSuppress: true)
        case .capsLock:
            guard type == .flagsChanged, trigger.keyCode == keyCode else { return .passThrough }
            return EventTapTriggerDecision(action: triggerPressed ? .up : .down, shouldSuppress: true)
        }
    }
}

public enum EventTapEventTypes {
    // NSSystemDefined is delivered through CGEvent with raw value 14 for media/brightness keys.
    public static let systemDefined = CGEventType(rawValue: 14)!
}
