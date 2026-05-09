import Foundation
import ApplicationServices
import Testing
@testable import OmniVoiceCore

@Suite("Text injection")
struct TextInjectionTests {
    @Test
    func injectionStrategyPrefersAXOnlyForSafeNativeTextControls() {
        #expect(TextInjectionStrategyPlanner.preferredStrategy(for: AccessibilityInjectionTraits(
            role: kAXTextFieldRole as String,
            isSecure: false,
            valueSettable: true,
            selectedTextSettable: false
        )) == .accessibility)
        #expect(TextInjectionStrategyPlanner.preferredStrategy(for: AccessibilityInjectionTraits(
            role: kAXTextAreaRole as String,
            isSecure: false,
            valueSettable: false,
            selectedTextSettable: true
        )) == .accessibility)
        #expect(TextInjectionStrategyPlanner.preferredStrategy(for: AccessibilityInjectionTraits(
            role: kAXTextAreaRole as String,
            isSecure: false,
            valueSettable: true,
            selectedTextSettable: true
        ), bundleIdentifier: "com.openai.codex", appName: "Codex") == .pasteboard)
        #expect(TextInjectionStrategyPlanner.preferredStrategy(for: AccessibilityInjectionTraits(
            role: kAXTextAreaRole as String,
            isSecure: false,
            valueSettable: true,
            selectedTextSettable: true
        ), bundleIdentifier: "com.duckduckgo.macos.browser", appName: "DuckDuckGo") == .pasteboard)
        #expect(TextInjectionStrategyPlanner.preferredStrategy(for: AccessibilityInjectionTraits(
            role: kAXTextAreaRole as String,
            isSecure: false,
            valueSettable: true,
            selectedTextSettable: true
        ), bundleIdentifier: "com.microsoft.VSCode", appName: "Code") == .pasteboard)
        #expect(TextInjectionStrategyPlanner.preferredStrategy(for: AccessibilityInjectionTraits(
            role: "AXWebArea",
            isSecure: false,
            valueSettable: true,
            selectedTextSettable: false
        ), bundleIdentifier: "com.apple.mail", appName: "Mail") == .pasteboard)
        #expect(TextInjectionStrategyPlanner.preferredStrategy(for: AccessibilityInjectionTraits(
            role: kAXTextFieldRole as String,
            isSecure: true,
            valueSettable: true,
            selectedTextSettable: true
        )) == .pasteboard)
        #expect(TextInjectionStrategyPlanner.preferredStrategy(for: AccessibilityInjectionTraits(
            role: "AXWebArea",
            isSecure: false,
            valueSettable: true,
            selectedTextSettable: true
        )) == .pasteboard)
        #expect(TextInjectionStrategyPlanner.preferredStrategy(for: AccessibilityInjectionTraits(
            role: kAXTextAreaRole as String,
            isSecure: false,
            valueSettable: false,
            selectedTextSettable: false
        )) == .pasteboard)
    }
    @Test
    func injectionStrategyClassifiesHiddenAXPasteFallbackApps() {
        #expect(TextInjectionStrategyPlanner.appClassification(
            bundleIdentifier: "com.tencent.xinWeChat",
            appName: "微信"
        ) == .hiddenAXPasteFallback)
        #expect(TextInjectionStrategyPlanner.appClassification(
            bundleIdentifier: "com.apple.TextEdit",
            appName: "文本编辑"
        ) == .nativeCandidate)

        let original = FocusSnapshot(
            pid: 100,
            appName: "微信",
            bundleIdentifier: "com.tencent.xinWeChat",
            role: nil,
            subrole: nil,
            isEditable: false,
            isSecure: false,
            failureReason: .targetAppUnresponsive
        )
        let current = FocusSnapshot(
            pid: 100,
            appName: "微信",
            bundleIdentifier: "com.tencent.xinWeChat",
            role: nil,
            subrole: nil,
            isEditable: false,
            isSecure: false,
            failureReason: .targetAppUnresponsive
        )
        let changedApp = FocusSnapshot(
            pid: 200,
            appName: "Mail",
            bundleIdentifier: "com.apple.mail",
            role: nil,
            subrole: nil,
            isEditable: false,
            isSecure: false,
            failureReason: .targetAppUnresponsive
        )
        let secureCurrent = FocusSnapshot(
            pid: 100,
            appName: "微信",
            bundleIdentifier: "com.tencent.xinWeChat",
            role: nil,
            subrole: nil,
            isEditable: false,
            isSecure: true,
            failureReason: .targetAppUnresponsive
        )

        #expect(TextInjectionStrategyPlanner.allowsHiddenAXPasteFallback(current: current, original: original))
        #expect(!TextInjectionStrategyPlanner.allowsHiddenAXPasteFallback(current: changedApp, original: original))
        #expect(!TextInjectionStrategyPlanner.allowsHiddenAXPasteFallback(current: secureCurrent, original: original))
    }
    @Test
    func axWriteVerificationRejectsReadableUnchangedValues() {
        let before = "hello world"
        let range = NSRange(location: 6, length: 5)
        let expected = AXWriteVerification.expectedValue(beforeValue: before, selectedRange: range, replacement: "OmniVoice")

        #expect(expected == "hello OmniVoice")
        #expect(AXWriteVerification.verifies(
            beforeValue: before,
            expectedValue: expected,
            afterValue: "hello OmniVoice",
            insertedText: "OmniVoice"
        ))
        #expect(!AXWriteVerification.verifies(
            beforeValue: before,
            expectedValue: expected,
            afterValue: before,
            insertedText: "OmniVoice"
        ))
        #expect(!AXWriteVerification.verifies(
            beforeValue: before,
            expectedValue: nil,
            afterValue: before,
            insertedText: "OmniVoice"
        ))
        #expect(AXWriteVerification.verifies(
            beforeValue: before,
            expectedValue: nil,
            afterValue: "hello world OmniVoice",
            insertedText: "OmniVoice"
        ))
        #expect(AXWriteVerification.verifies(
            beforeValue: before,
            expectedValue: expected,
            afterValue: nil,
            insertedText: "OmniVoice"
        ))
        #expect(AXWriteVerification.expectedValue(
            beforeValue: before,
            selectedRange: NSRange(location: 50, length: 1),
            replacement: "x"
        ) == nil)
    }

    @Test
    func accessibilityElementReaderSafelyExtractsRangeValues() {
        var cfRange = CFRange(location: 4, length: 2)
        let rangeValue = AXValueCreate(.cfRange, &cfRange)
        #expect(AccessibilityElementReader.range(from: rangeValue) == NSRange(location: 4, length: 2))

        var point = CGPoint(x: 1, y: 2)
        let pointValue = AXValueCreate(.cgPoint, &point)
        #expect(AccessibilityElementReader.range(from: pointValue) == nil)
        #expect(AccessibilityElementReader.range(from: "not an AXValue" as CFString) == nil)
        #expect(AccessibilityElementReader.element(from: "not an AXElement" as CFString) == nil)
    }
}
