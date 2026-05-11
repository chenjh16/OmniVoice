import AppKit
import Foundation
import OmniVoiceCore

extension InjectionE2ECommand {
    @MainActor
    static func runHUDPreview(parser: InjectionE2EArgumentParser, startedAt: Date) async -> Int {
        var result: [String: Any] = [
            "ok": false,
            "mode": "hud_preview_e2e",
            "started_at": ISO8601DateFormatter().string(from: startedAt)
        ]
        do {
            let language = uiLanguageValue(parser: parser) ?? .chinese
            let strings = UIStrings(language: language)
            let style = parser.value(after: "--hud-style").map(HUDVisualStyle.safeSelection) ?? .darkCapsule
            let previewText = parser.value(after: "--preview-text")?.nilIfBlank
                ?? (language == .chinese
                    ? "这是一个实时语音识别草稿，松手后才会生成最终转写。"
                    : "This is a live speech draft; final text is produced after release.")
            let previewBadge = parser.value(after: "--preview-badge")?.nilIfBlank ?? strings.liveASRPreviewBadge
            let artifactRecorder = try artifactRecorder(parser: parser)
            let hud = DictationHUDController()
            hud.setVisualStyle(style)
            hud.showListening(text: strings.listening)
            hud.updateListeningPreview(previewText, badge: previewBadge)
            let holdMilliseconds = max(0, Int(parser.value(after: "--hold-ms") ?? "350") ?? 350)
            try? await Task.sleep(nanoseconds: UInt64(holdMilliseconds) * 1_000_000)
            let snapshot = hud.diagnosticSnapshot
            let pngData = hud.renderedPNGData()
            artifactRecorder?.record(AutomationEvent(
                stage: "hud_preview_stable",
                details: [
                    "hud_style": style.rawValue,
                    "ui_language": language.rawValue,
                    "badge": previewBadge,
                    "preview_chars": "\(previewText.count)"
                ],
                surface: snapshot,
                screenshotPNGData: pngData
            ))
            hud.hide()
            result["ok"] = pngData != nil
            result["hud_style"] = style.rawValue
            result["ui_language"] = language.rawValue
            result["preview_chars"] = previewText.count
            result["badge"] = previewBadge
            result["hold_ms"] = holdMilliseconds
            result["screenshot_captured"] = pngData != nil
            result["gui_artifacts_dir"] = artifactRecorder?.directoryPath as Any? ?? NSNull()
            result["elapsed_ms"] = Int(Date().timeIntervalSince(startedAt) * 1000)
            writeJSON(result)
            return pngData != nil ? 0 : 1
        } catch {
            result["error"] = "unexpected_error"
            result["elapsed_ms"] = Int(Date().timeIntervalSince(startedAt) * 1000)
            writeJSON(result)
            return 1
        }
    }
}
