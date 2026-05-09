import ApplicationServices
import Foundation

enum AccessibilityElementReader {
    static let defaultMessagingTimeout: Float = 0.35

    static func setMessagingTimeout(_ element: AXUIElement, timeout: Float = defaultMessagingTimeout) {
        AXUIElementSetMessagingTimeout(element, timeout)
    }

    static func element(from value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // Swift cannot express this CoreFoundation cast conditionally; the CFTypeID guard is the safety check.
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    static func axValue(from value: CFTypeRef?) -> AXValue? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        // Swift cannot express this CoreFoundation cast conditionally; the CFTypeID guard is the safety check.
        return unsafeBitCast(value, to: AXValue.self)
    }

    static func copyElement(_ element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let copied = self.element(from: value) else {
            return nil
        }
        setMessagingTimeout(copied)
        return copied
    }

    static func copyElementArray(_ element: AXUIElement, attribute: CFString) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let array = value as? [Any] else {
            return []
        }
        return array.compactMap { item in
            guard let child = self.element(from: item as AnyObject) else { return nil }
            setMessagingTimeout(child)
            return child
        }
    }

    static func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    static func selectedTextRange(element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return range(from: value)
    }

    static func range(from value: CFTypeRef?) -> NSRange? {
        guard let axValue = axValue(from: value) else { return nil }
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    static func setSelectedTextRange(element: AXUIElement, location: Int) {
        var range = CFRange(location: location, length: 0)
        guard let value = AXValueCreate(.cfRange, &range) else { return }
        _ = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
    }

    static func isAttributeSettable(_ element: AXUIElement, _ attribute: CFString) -> Bool {
        var settable = DarwinBoolean(false)
        _ = AXUIElementIsAttributeSettable(element, attribute, &settable)
        return settable.boolValue
    }
}
