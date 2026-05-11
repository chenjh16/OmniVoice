import AppKit
import CoreGraphics
import Foundation

@MainActor
public final class TextInjector {
    public struct Options: Equatable, Sendable {
        public let timeoutSeconds: TimeInterval
        public let pasteWaitNanoseconds: UInt64

        public init(timeoutSeconds: TimeInterval = 2.5, pasteWaitNanoseconds: UInt64 = 550_000_000) {
            self.timeoutSeconds = timeoutSeconds
            self.pasteWaitNanoseconds = pasteWaitNanoseconds
        }
    }

    public var onDiagnostic: ((RuntimeDiagnostic) -> Void)?

    let options: Options

    public init(options: Options = Options(), onDiagnostic: ((RuntimeDiagnostic) -> Void)? = nil) {
        self.options = options
        self.onDiagnostic = onDiagnostic
    }

    public func insertFinalText(
        _ text: String,
        originalFocus: FocusSnapshot?,
        targetBundleIdentifier: String? = nil
    ) async -> TextInjectionResult {
        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(options.timeoutSeconds)
        var pasteboardSnapshot: PasteboardSnapshot?
        var shouldRestorePasteboard = false

        emitInjectionDiagnostic(
            stage: "injection_start",
            details: [
                "text_chars": "\(text.count)",
                "timeout_seconds": String(format: "%.2f", options.timeoutSeconds)
            ].merging(originalFocus?.diagnosticDetails(prefix: "original") ?? [:]) { current, _ in current }
        )

        defer {
            if shouldRestorePasteboard, let pasteboardSnapshot {
                let restored = pasteboardSnapshot.restore()
                emitInjectionDiagnostic(
                    stage: "pasteboard_restore",
                    details: [
                        "pasteboard_items": "\(pasteboardSnapshot.itemCount)",
                        "pasteboard_types": "\(pasteboardSnapshot.typeCount)",
                        "pasteboard_restored": String(restored)
                    ]
                )
            }
        }

        guard !isTimedOut(deadline: deadline, stage: "before_focus") else {
            return .fallback(.insertionTimeout)
        }

        let current = captureFocusSnapshot(targetBundleIdentifier: targetBundleIdentifier)
        emitInjectionDiagnostic(stage: "focus_before_insert", details: current.diagnosticDetails(prefix: "current"))
        let hiddenAXPasteFallback = TextInjectionStrategyPlanner.allowsHiddenAXPasteFallback(
            current: current,
            original: originalFocus
        )
        guard current.canAutoInsert || hiddenAXPasteFallback else {
            emitInjectionDiagnostic(
                stage: "injection_fallback",
                details: current.diagnosticDetails(prefix: "current"),
                errorKind: current.failureReason.rawValue
            )
            return .fallback(current.failureReason)
        }
        if hiddenAXPasteFallback {
            emitInjectionDiagnostic(
                stage: "hidden_ax_paste_fallback",
                details: current.diagnosticDetails(prefix: "current")
            )
        }
        if let originalPID = originalFocus?.pid,
           let currentPID = current.pid,
           originalPID != currentPID {
            emitInjectionDiagnostic(
                stage: "injection_fallback",
                details: [
                    "original_pid": "\(originalPID)",
                    "current_pid": "\(currentPID)"
                ],
                errorKind: FocusFailureReason.noFocusedElement.rawValue
            )
            return .fallback(.noFocusedElement)
        }

        guard !isTimedOut(deadline: deadline, stage: "after_focus") else {
            return .fallback(.insertionTimeout)
        }

        if !hiddenAXPasteFallback,
           let element = focusedElement(targetBundleIdentifier: targetBundleIdentifier),
           await attemptAccessibilityInsertion(text: text, element: element, focus: current) {
            emitInjectionDiagnostic(stage: "injection_inserted", details: ["method": "accessibility"])
            return .inserted
        }

        guard !isTimedOut(deadline: deadline, stage: "after_ax_attempt") else {
            return .fallback(.insertionTimeout)
        }

        let inputSourceSnapshot = InputSourceManager.currentInputSource()
        let shouldSwitchInputSource = InputSourceManager.currentInputSourceIsCJK()
        emitInjectionDiagnostic(
            stage: "input_source_snapshot",
            details: [
                "input_source_id": inputSourceSnapshot.identifier ?? "unknown",
                "input_source_is_cjk": String(shouldSwitchInputSource)
            ]
        )
        if shouldSwitchInputSource {
            emitInjectionDiagnostic(
                stage: "input_source_switch_skipped_by_default",
                details: ["input_source_id": inputSourceSnapshot.identifier ?? "unknown"]
            )
        }

        guard !isTimedOut(deadline: deadline, stage: "after_input_source") else {
            return .fallback(.insertionTimeout)
        }

        pasteboardSnapshot = PasteboardSnapshot.capture()
        shouldRestorePasteboard = true
        emitInjectionDiagnostic(
            stage: "pasteboard_capture",
            details: [
                "pasteboard_items": "\(pasteboardSnapshot?.itemCount ?? 0)",
                "pasteboard_types": "\(pasteboardSnapshot?.typeCount ?? 0)"
            ]
        )

        let pasteboardChangeCount = NSPasteboard.general.clearContents()
        let pasteboardWriteSucceeded = NSPasteboard.general.setString(text, forType: .string)
        emitInjectionDiagnostic(
            stage: "pasteboard_write",
            details: [
                "pasteboard_change_count": "\(pasteboardChangeCount)",
                "pasteboard_write_succeeded": String(pasteboardWriteSucceeded),
                "text_chars": "\(text.count)"
            ],
            errorKind: pasteboardWriteSucceeded ? nil : "pasteboard_write_failed"
        )
        guard pasteboardWriteSucceeded else {
            return .fallback(.pasteEventFailed)
        }

        guard !isTimedOut(deadline: deadline, stage: "before_paste_event") else {
            return .fallback(.insertionTimeout)
        }

        emitInjectionDiagnostic(stage: "simulate_paste_start")
        guard simulatePaste() else {
            emitInjectionDiagnostic(
                stage: "simulate_paste_result",
                details: ["paste_event_posted": "false"],
                errorKind: FocusFailureReason.pasteEventFailed.rawValue
            )
            return .fallback(.pasteEventFailed)
        }
        emitInjectionDiagnostic(stage: "simulate_paste_result", details: ["paste_event_posted": "true"])

        do {
            try await Task.sleep(nanoseconds: min(pasteWaitNanoseconds(for: current), remainingNanoseconds(until: deadline)))
        } catch {
            emitInjectionDiagnostic(
                stage: "injection_cancelled",
                details: ["elapsed_seconds": String(format: "%.3f", Date().timeIntervalSince(startedAt))],
                errorKind: FocusFailureReason.insertionCancelled.rawValue
            )
            return .fallback(.insertionCancelled)
        }

        if isTimedOut(deadline: deadline, stage: "after_paste_wait") {
            return .fallback(.insertionTimeout)
        }

        emitInjectionDiagnostic(
            stage: "paste_wait_done",
            details: ["elapsed_seconds": String(format: "%.3f", Date().timeIntervalSince(startedAt))]
        )
        emitInjectionDiagnostic(stage: "injection_inserted", details: ["method": "pasteboard"])
        return .inserted
    }

    private func simulatePaste() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private func pasteWaitNanoseconds(for focus: FocusSnapshot) -> UInt64 {
        let classification = TextInjectionStrategyPlanner.appClassification(
            bundleIdentifier: focus.bundleIdentifier,
            appName: focus.appName
        )
        guard classification != .nativeCandidate else {
            return options.pasteWaitNanoseconds
        }
        return max(options.pasteWaitNanoseconds, 900_000_000)
    }

    private func isTimedOut(deadline: Date, stage: String) -> Bool {
        guard Date() >= deadline else { return false }
        emitInjectionDiagnostic(
            stage: "injection_timeout",
            details: ["timeout_stage": stage],
            errorKind: FocusFailureReason.insertionTimeout.rawValue
        )
        return true
    }

    private func remainingNanoseconds(until deadline: Date) -> UInt64 {
        let remaining = max(0.05, deadline.timeIntervalSinceNow)
        return UInt64(remaining * 1_000_000_000)
    }

    func emitInjectionDiagnostic(
        stage: String,
        details: [String: String] = [:],
        errorKind: String? = nil
    ) {
        let diagnostic = RuntimeDiagnostic(
            stage: stage,
            host: "local",
            errorKind: errorKind,
            details: details.mapValues { value in
                if value.count > 160 {
                    return String(value.prefix(160)) + "..."
                }
                return value
            }
        )
        RuntimeDiagnostic.log(diagnostic)
        onDiagnostic?(diagnostic)
    }
}
