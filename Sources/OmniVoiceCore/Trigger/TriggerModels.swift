import Foundation
import CoreGraphics

public enum TriggerKind: String, Codable, Sendable {
    case fnGlobe
    case functionKey
    case modifier
    case capsLock
}

public enum TriggerLocation: String, Codable, Sendable {
    case any
    case left
    case right
}

public struct TriggerKey: Codable, Equatable, Hashable, Sendable {
    public let identifier: String
    public let displayLabel: String
    public let keyCode: Int?
    public let modifierFlagsRawValue: UInt64
    public let location: TriggerLocation
    public let kind: TriggerKind

    public init(
        identifier: String,
        displayLabel: String,
        keyCode: Int?,
        modifierFlagsRawValue: UInt64 = 0,
        location: TriggerLocation = .any,
        kind: TriggerKind
    ) {
        self.identifier = identifier
        self.displayLabel = displayLabel
        self.keyCode = keyCode
        self.modifierFlagsRawValue = modifierFlagsRawValue
        self.location = location
        self.kind = kind
    }

    public static let fnGlobe = TriggerKey(
        identifier: "fn-globe",
        displayLabel: "Fn/Globe",
        keyCode: nil,
        modifierFlagsRawValue: CGEventFlags.maskSecondaryFn.rawValue,
        location: .any,
        kind: .fnGlobe
    )

    public static let leftControl = TriggerKey(
        identifier: "modifier-left-control",
        displayLabel: "Left Control",
        keyCode: 59,
        modifierFlagsRawValue: CGEventFlags.maskControl.rawValue,
        location: .left,
        kind: .modifier
    )

    public static let defaultTrigger = fnGlobe

    public static let functionKeys: [TriggerKey] = [
        ("F1", 122), ("F2", 120), ("F3", 99), ("F4", 118), ("F5", 96),
        ("F6", 97), ("F7", 98), ("F8", 100), ("F9", 101), ("F10", 109),
        ("F11", 103), ("F12", 111)
    ].map { label, code in
        TriggerKey(
            identifier: "function-\(label.lowercased())",
            displayLabel: label,
            keyCode: code,
            kind: .functionKey
        )
    }

    public static let modifierKeys: [TriggerKey] = [
        TriggerKey(
            identifier: "modifier-left-shift",
            displayLabel: "Left Shift",
            keyCode: 56,
            modifierFlagsRawValue: CGEventFlags.maskShift.rawValue,
            location: .left,
            kind: .modifier
        ),
        TriggerKey(
            identifier: "modifier-right-shift",
            displayLabel: "Right Shift",
            keyCode: 60,
            modifierFlagsRawValue: CGEventFlags.maskShift.rawValue,
            location: .right,
            kind: .modifier
        ),
        leftControl,
        TriggerKey(
            identifier: "modifier-right-control",
            displayLabel: "Right Control",
            keyCode: 62,
            modifierFlagsRawValue: CGEventFlags.maskControl.rawValue,
            location: .right,
            kind: .modifier
        ),
        TriggerKey(
            identifier: "modifier-left-option",
            displayLabel: "Left Option",
            keyCode: 58,
            modifierFlagsRawValue: CGEventFlags.maskAlternate.rawValue,
            location: .left,
            kind: .modifier
        ),
        TriggerKey(
            identifier: "modifier-right-option",
            displayLabel: "Right Option",
            keyCode: 61,
            modifierFlagsRawValue: CGEventFlags.maskAlternate.rawValue,
            location: .right,
            kind: .modifier
        ),
        TriggerKey(
            identifier: "modifier-left-command",
            displayLabel: "Left Command",
            keyCode: 55,
            modifierFlagsRawValue: CGEventFlags.maskCommand.rawValue,
            location: .left,
            kind: .modifier
        ),
        TriggerKey(
            identifier: "modifier-right-command",
            displayLabel: "Right Command",
            keyCode: 54,
            modifierFlagsRawValue: CGEventFlags.maskCommand.rawValue,
            location: .right,
            kind: .modifier
        )
    ]

    public static let capsLock = TriggerKey(
        identifier: "caps-lock",
        displayLabel: "Caps Lock",
        keyCode: 57,
        modifierFlagsRawValue: CGEventFlags.maskAlphaShift.rawValue,
        location: .any,
        kind: .capsLock
    )

    public static var allCandidates: [TriggerKey] {
        [fnGlobe] + functionKeys + modifierKeys + [capsLock]
    }

    public static func candidate(identifier: String?) -> TriggerKey {
        guard let identifier,
              let candidate = allCandidates.first(where: { $0.identifier == identifier }) else {
            return .defaultTrigger
        }
        return candidate
    }

    public static func captureCandidate(keyCode: Int?, includesFunctionModifier: Bool = false) -> TriggerKey? {
        if includesFunctionModifier {
            return .fnGlobe
        }
        guard let keyCode else { return nil }
        if let functionKey = functionKeys.first(where: { $0.keyCode == keyCode }) {
            return functionKey
        }
        if let modifierKey = modifierKeys.first(where: { $0.keyCode == keyCode }) {
            return modifierKey
        }
        if capsLock.keyCode == keyCode {
            return .capsLock
        }
        return nil
    }
}
