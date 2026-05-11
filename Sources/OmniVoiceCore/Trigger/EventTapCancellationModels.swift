import CoreGraphics
import Foundation

public enum EventTapFnCombinationCancellation {
    public static func cancelReason(
        trigger: TriggerKey,
        type: CGEventType,
        triggerPressed: Bool
    ) -> EventTapCancellationReason? {
        guard trigger.kind == .fnGlobe, triggerPressed else { return nil }
        return type == .keyDown || type == EventTapEventTypes.systemDefined ? .triggerCombination : nil
    }

    public static func shouldCancel(
        trigger: TriggerKey,
        type: CGEventType,
        triggerPressed: Bool
    ) -> Bool {
        cancelReason(trigger: trigger, type: type, triggerPressed: triggerPressed) != nil
    }
}

public enum FnEscapeRescueDetector {
    public static let escapeKeyCode = 53

    public static func shouldRescue(
        type: CGEventType,
        keyCode: Int,
        flags: CGEventFlags
    ) -> Bool {
        type == .keyDown &&
        keyCode == escapeKeyCode &&
        flags.contains(.maskSecondaryFn)
    }
}

public enum EventTapEscapeCancellation {
    public static func cancelReason(
        type: CGEventType,
        keyCode: Int,
        cancellationActive: Bool
    ) -> EventTapCancellationReason? {
        guard cancellationActive,
              type == .keyDown,
              keyCode == FnEscapeRescueDetector.escapeKeyCode else {
            return nil
        }
        return .escapeKey
    }
}
