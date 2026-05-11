import ApplicationServices
import Foundation

@MainActor
extension TextInjector {
    func attemptAccessibilityInsertion(text: String, element: AXUIElement, focus: FocusSnapshot) async -> Bool {
        let traits = accessibilityTraits(element: element, focus: focus)
        let strategy = TextInjectionStrategyPlanner.preferredStrategy(
            for: traits,
            bundleIdentifier: focus.bundleIdentifier,
            appName: focus.appName
        )
        emitInjectionDiagnostic(
            stage: "ax_insert_decision",
            details: [
                "ax_strategy": strategy == .accessibility ? "accessibility" : "pasteboard",
                "ax_app_classification": "\(TextInjectionStrategyPlanner.appClassification(bundleIdentifier: focus.bundleIdentifier, appName: focus.appName))",
                "ax_role": traits.role ?? "unknown",
                "ax_value_settable": String(traits.valueSettable),
                "ax_selected_text_settable": String(traits.selectedTextSettable)
            ]
        )
        guard strategy == .accessibility else { return false }

        emitInjectionDiagnostic(stage: "ax_insert_attempt")
        if traits.selectedTextSettable {
            let beforeValue = AccessibilityElementReader.stringAttribute(element, kAXValueAttribute as CFString)
            let selectedRange = AccessibilityElementReader.selectedTextRange(element: element)
            let expectedValue = beforeValue.flatMap { before in
                selectedRange.flatMap { AXWriteVerification.expectedValue(beforeValue: before, selectedRange: $0, replacement: text) }
            }
            let result = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
            emitInjectionDiagnostic(
                stage: "ax_insert_result",
                details: [
                    "ax_method": "selected_text",
                    "ax_result": "\(result.rawValue)",
                    "ax_before_len": beforeValue.map { "\(($0 as NSString).length)" } ?? "unreadable",
                    "ax_expected_len": expectedValue.map { "\(($0 as NSString).length)" } ?? "unavailable"
                ],
                errorKind: result == .success ? nil : "ax_selected_text_failed"
            )
            if result == .success,
               await verifyAXWrite(
                   element: element,
                   method: "selected_text",
                   beforeValue: beforeValue,
                   expectedValue: expectedValue,
                   insertedText: text
               ) {
                return true
            }
        }

        guard traits.valueSettable,
              let currentValue = AccessibilityElementReader.stringAttribute(element, kAXValueAttribute as CFString),
              let selectedRange = AccessibilityElementReader.selectedTextRange(element: element) else {
            emitInjectionDiagnostic(stage: "ax_insert_result", errorKind: "ax_value_range_unavailable")
            return false
        }

        let utf16Count = (currentValue as NSString).length
        guard selectedRange.location >= 0,
              selectedRange.length >= 0,
              selectedRange.location + selectedRange.length <= utf16Count else {
            emitInjectionDiagnostic(stage: "ax_insert_result", errorKind: "ax_selected_range_invalid")
            return false
        }

        let nextValue = (currentValue as NSString).replacingCharacters(in: selectedRange, with: text)
        let result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, nextValue as CFString)
        emitInjectionDiagnostic(
            stage: "ax_insert_result",
            details: [
                "ax_method": "value_replace_range",
                "ax_result": "\(result.rawValue)"
            ],
            errorKind: result == .success ? nil : "ax_value_set_failed"
        )
        if result == .success {
            let verified = await verifyAXWrite(
                element: element,
                method: "value_replace_range",
                beforeValue: currentValue,
                expectedValue: nextValue,
                insertedText: text
            )
            if verified {
                AccessibilityElementReader.setSelectedTextRange(
                    element: element,
                    location: selectedRange.location + (text as NSString).length
                )
                return true
            }
        }
        return false
    }

    func verifyAXWrite(
        element: AXUIElement,
        method: String,
        beforeValue: String?,
        expectedValue: String?,
        insertedText: String
    ) async -> Bool {
        try? await Task.sleep(nanoseconds: 80_000_000)
        let afterValue = AccessibilityElementReader.stringAttribute(element, kAXValueAttribute as CFString)
        let verified = AXWriteVerification.verifies(
            beforeValue: beforeValue,
            expectedValue: expectedValue,
            afterValue: afterValue,
            insertedText: insertedText
        )
        emitInjectionDiagnostic(
            stage: "ax_insert_verify",
            details: [
                "ax_method": method,
                "ax_verified": String(verified),
                "ax_before_len": beforeValue.map { "\(($0 as NSString).length)" } ?? "unreadable",
                "ax_after_len": afterValue.map { "\(($0 as NSString).length)" } ?? "unreadable",
                "ax_expected_len": expectedValue.map { "\(($0 as NSString).length)" } ?? "unavailable"
            ],
            errorKind: verified ? nil : "ax_value_unchanged"
        )
        return verified
    }

    func accessibilityTraits(element: AXUIElement, focus: FocusSnapshot) -> AccessibilityInjectionTraits {
        return AccessibilityInjectionTraits(
            role: focus.role,
            isSecure: focus.isSecure,
            valueSettable: AccessibilityElementReader.isAttributeSettable(element, kAXValueAttribute as CFString),
            selectedTextSettable: AccessibilityElementReader.isAttributeSettable(element, kAXSelectedTextAttribute as CFString)
        )
    }
}
