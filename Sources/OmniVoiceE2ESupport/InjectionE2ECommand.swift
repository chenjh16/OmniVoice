import AppKit
import Darwin
import Dispatch
import Foundation
import OmniVoiceCore

public enum InjectionE2ECommand {
    public static let trigger = "--omnivoice-injection-e2e"
    public static let hudPreviewTrigger = "--omnivoice-hud-preview-e2e"

    public static func runFromMain(arguments: [String]) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        DispatchQueue.main.async {
            Task { @MainActor in
                let exitCode = await run(arguments: arguments)
                Darwin.exit(Int32(exitCode))
            }
        }
        app.run()
        Darwin.exit(1)
    }

    @MainActor
    public static func run(arguments: [String]) async -> Int {
        let parser = InjectionE2EArgumentParser(arguments: arguments)
        if parser.has(hudPreviewTrigger) {
            if parser.has("--help") {
                print(usage)
                return 0
            }
            return await runHUDPreview(parser: parser, startedAt: Date())
        }

        guard parser.has(trigger) else {
            writeJSON(["ok": false, "error": "missing_trigger"])
            return 64
        }
        if parser.has("--help") {
            print(usage)
            return 0
        }

        let startedAt = Date()
        var result: [String: Any] = [
            "ok": false,
            "mode": "injection_e2e",
            "started_at": ISO8601DateFormatter().string(from: startedAt)
        ]

        if let targetBundle = parser.value(after: "--target-bundle") {
            result["target_bundle"] = targetBundle
            result["target_activated"] = activate(bundleIdentifier: targetBundle)
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        do {
            if parser.value(after: "--replay-wav") != nil {
                return await runReplay(parser: parser, startedAt: startedAt, initialResult: result)
            }

            let transcript = try await transcriptText(parser: parser)
            result["transcript_chars"] = transcript.count
            result["transcript_source"] = "fixture_wav_http"
            let expectedKeywords = parser.values(after: "--expect-keyword")
            if let quality = TranscriptQualitySummary.evaluate(finalText: transcript, expectedKeywords: expectedKeywords) {
                addQualitySummary(quality, to: &result)
            }

            let injector = TextInjector()
            let originalFocus = injector.captureFocusSnapshot(
                targetBundleIdentifier: parser.value(after: "--target-bundle")
            )
            result["original_bundle"] = originalFocus.bundleIdentifier ?? NSNull()
            result["original_app"] = originalFocus.appName ?? NSNull()
            result["original_failure"] = originalFocus.failureReason.rawValue

            let injectionResult = await injector.insertFinalText(transcript, originalFocus: originalFocus)
            switch injectionResult {
            case .inserted:
                let qualityPassed = (result["quality_passed"] as? Bool) ?? true
                result["ok"] = qualityPassed
                result["injection_result"] = "inserted"
                result["elapsed_ms"] = Int(Date().timeIntervalSince(startedAt) * 1000)
                writeJSON(result)
                return qualityPassed ? 0 : 3
            case let .fallback(reason):
                result["injection_result"] = "fallback"
                result["fallback_reason"] = reason.rawValue
                result["elapsed_ms"] = Int(Date().timeIntervalSince(startedAt) * 1000)
                writeJSON(result)
                return 2
            }
        } catch let error as InjectionE2ECommandError {
            result["error"] = error.rawValue
            result["elapsed_ms"] = Int(Date().timeIntervalSince(startedAt) * 1000)
            writeJSON(result)
            return 64
        } catch let error as MimoAPIError {
            result["error"] = error.diagnosticKind
            result["elapsed_ms"] = Int(Date().timeIntervalSince(startedAt) * 1000)
            writeJSON(result)
            return 69
        } catch {
            result["error"] = "unexpected_error"
            result["elapsed_ms"] = Int(Date().timeIntervalSince(startedAt) * 1000)
            writeJSON(result)
            return 1
        }
    }
}
