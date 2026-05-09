import Carbon
import Foundation

public struct InputSourceSnapshot {
    fileprivate let source: TISInputSource?
    public let identifier: String?

    public init(source: TISInputSource?, identifier: String?) {
        self.source = source
        self.identifier = identifier
    }
}

public enum InputSourceManager {
    public static func currentInputSource() -> InputSourceSnapshot {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return InputSourceSnapshot(source: nil, identifier: nil)
        }
        return InputSourceSnapshot(source: source, identifier: inputSourceID(source))
    }

    public static func currentInputSourceIsCJK() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return false
        }
        if inputSourceIsASCIICapable(source) {
            return false
        }
        let id = inputSourceID(source)?.lowercased() ?? ""
        return [
            "scim", "tcim", "pinyin", "wubi", "zh", "chinese",
            "kotoeri", "japanese", "hiragana", "katakana",
            "korean", "hangul"
        ].contains { id.contains($0) }
    }

    @discardableResult
    public static func switchToASCIIInputSource() -> Bool {
        if let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() {
            return TISSelectInputSource(source) == noErr
        }
        if let source = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() {
            return TISSelectInputSource(source) == noErr
        }
        return false
    }

    @discardableResult
    public static func restore(_ snapshot: InputSourceSnapshot) -> Bool {
        guard let source = snapshot.source else { return false }
        return TISSelectInputSource(source) == noErr
    }

    private static func inputSourceID(_ source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func inputSourceIsASCIICapable(_ source: TISInputSource) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) else {
            return false
        }
        let value = Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
        return CFBooleanGetValue(value)
    }
}
