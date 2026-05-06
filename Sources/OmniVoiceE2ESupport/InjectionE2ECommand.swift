import AppKit
import Darwin
import Dispatch
import Foundation
import OmniVoiceCore

public enum InjectionE2ECommand {
    public static let trigger = "--omnivoice-injection-e2e"

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
        let parser = ArgumentParser(arguments: arguments)
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
                result["ok"] = true
                result["injection_result"] = "inserted"
                result["elapsed_ms"] = Int(Date().timeIntervalSince(startedAt) * 1000)
                writeJSON(result)
                return 0
            case let .fallback(reason):
                result["injection_result"] = "fallback"
                result["fallback_reason"] = reason.rawValue
                result["elapsed_ms"] = Int(Date().timeIntervalSince(startedAt) * 1000)
                writeJSON(result)
                return 2
            }
        } catch let error as CommandError {
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

    private static let usage = """
    OmniVoice injection E2E helper

    Usage:
      OmniVoice --omnivoice-injection-e2e --fixture-wav /tmp/sample.wav [--config-path /tmp/config.jsonc] [--style concise] [--model mimo-v2.5] [--target-bundle BUNDLE]
      OmniVoice --omnivoice-injection-e2e --replay-wav /tmp/sample.wav [--config-path /tmp/config.jsonc] [--style concise] [--model mimo-v2.5] [--hud-style darkCapsule] [--ui-language en] [--replay-speed 1.0] [--target-bundle BUNDLE] [--force-action-panel] [--gui-artifacts-dir DIR] [--record-gui-frames] [--gui-frame-interval-ms 83]

    Notes:
      The JSON result is redacted: it includes character counts, strategy outcomes, bundle ids, and error classes, but never the transcript or clipboard contents.
      --fixture-wav is a fast transcription + injection helper. --replay-wav drives the recording HUD, RMS waveform, transcription HUD, streaming delta preview, and final injection path.
      --record-gui-frames samples OmniVoice HUD/ActionPanel surfaces into the GUI artifacts directory without using macOS screen recording.
      Mock transcription should be provided by an OpenAI-compatible local mock service and selected through --config-path.
    """

    private enum CommandError: String, Error {
        case missingTranscriptInput = "missing_transcript_input"
        case invalidFixtureWAV = "invalid_fixture_wav"
        case fixtureWAVReadFailed = "fixture_wav_read_failed"
        case replayWAVReadFailed = "replay_wav_read_failed"
        case invalidReplayWAV = "invalid_replay_wav"
        case invalidReplaySpeed = "invalid_replay_speed"
    }

    @MainActor
    private static func runReplay(
        parser: ArgumentParser,
        startedAt: Date,
        initialResult: [String: Any]
    ) async -> Int {
        var result = initialResult
        result["mode"] = "recording_replay_e2e"

        do {
            let wavData = try replayWAVData(parser: parser)
            let speed = try replaySpeed(parser: parser)
            let model = parser.value(after: "--model").flatMap(AllowedSpeechModel.init(rawValue:)) ?? SettingsStore.shared.selectedModel
            let styleSelection = TranscriptionStyleSelection(rawValue: parser.value(after: "--style") ?? SettingsStore.shared.transcriptionStyleSelection.rawValue)
            let hudVisualStyle = parser.value(after: "--hud-style").map(HUDVisualStyle.safeSelection)
            let uiLanguage = uiLanguageValue(parser: parser)
            let loader = configLoader(parser: parser)
            let config = loader.load().resolvingSource(using: [:])
            let artifactRecorder = try artifactRecorder(parser: parser)
            let forceActionPanel = parser.has("--force-action-panel")
            let recordGUIFrames = parser.has("--record-gui-frames")
            let guiFrameIntervalSeconds = guiFrameIntervalSeconds(parser: parser)

            result["model"] = model.rawValue
            result["style"] = styleSelection.rawValue
            result["hud_style"] = hudVisualStyle?.rawValue ?? SettingsStore.shared.hudVisualStyle.rawValue
            result["ui_language"] = uiLanguage?.rawValue ?? SettingsStore.shared.uiLanguage.rawValue
            result["replay_speed"] = speed
            result["record_gui_frames"] = recordGUIFrames
            result["gui_frame_interval_ms"] = Int(guiFrameIntervalSeconds * 1000)
            result["wav_bytes"] = wavData.count
            result["transcript_source"] = "replay_wav_http"
            result["config_source"] = parser.value(after: "--config-path") == nil ? "default_config" : "custom_config"
            result["base_url_host"] = config.baseURL.host ?? config.baseURL.absoluteString
            result["force_action_panel"] = forceActionPanel
            if let artifactRecorder {
                result["gui_artifacts_dir"] = artifactRecorder.directoryPath
            }
            if let duration = WAVEncoder.durationSecondsForPCM16Mono16kWAV(wavData) {
                result["fixture_duration_ms"] = Int(duration * 1000)
            }

            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            if let targetBundle = parser.value(after: "--target-bundle") {
                result["target_reactivated"] = activate(bundleIdentifier: targetBundle)
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
            let replaySource = try WAVReplayRecordingSource(wavData: wavData, replaySpeed: speed)
            let automation = await OmniVoiceAutomationRunner.runRecordingReplay(
                recordingSource: replaySource,
                configLoader: loader,
                eventSink: artifactRecorder,
                options: RecordingReplayAutomationOptions(
                    model: model,
                    styleSelection: styleSelection,
                    forceAutoInsert: !forceActionPanel,
                    forceActionPanel: forceActionPanel,
                    targetBundleIdentifier: parser.value(after: "--target-bundle"),
                    hudVisualStyle: hudVisualStyle,
                    uiLanguage: uiLanguage,
                    recordGUIFrames: recordGUIFrames,
                    guiFrameIntervalSeconds: guiFrameIntervalSeconds
                )
            )

            result["ok"] = automation.ok
            result["recording_seconds"] = jsonValue(automation.recordingSeconds.map { String(format: "%.3f", $0) })
            result["recording_wav_bytes"] = jsonValue(automation.wavBytes)
            result["recording_rms"] = jsonValue(automation.overallRMS.map { String(format: "%.5f", $0) })
            result["original_bundle"] = jsonValue(automation.originalBundleIdentifier)
            result["original_app"] = jsonValue(automation.originalAppName)
            result["original_failure"] = jsonValue(automation.originalFocusFailure)
            result["injection_result"] = jsonValue(automation.injectionResult)
            result["fallback_reason"] = jsonValue(automation.fallbackReason)
            result["error"] = jsonValue(automation.errorKind)
            result["elapsed_ms"] = Int(Date().timeIntervalSince(startedAt) * 1000)
            writeJSON(result)
            if automation.ok {
                return 0
            }
            if automation.injectionResult == "fallback" {
                return 2
            }
            return 1
        } catch let error as CommandError {
            result["error"] = error.rawValue
            result["elapsed_ms"] = Int(Date().timeIntervalSince(startedAt) * 1000)
            writeJSON(result)
            return 64
        } catch {
            result["error"] = "unexpected_error"
            result["elapsed_ms"] = Int(Date().timeIntervalSince(startedAt) * 1000)
            writeJSON(result)
            return 1
        }
    }

    private static func transcriptText(parser: ArgumentParser) async throws -> String {
        guard let wavPath = parser.value(after: "--fixture-wav")?.nilIfBlank else {
            throw CommandError.missingTranscriptInput
        }
        let wavURL = URL(fileURLWithPath: wavPath)
        guard let wavData = try? Data(contentsOf: wavURL) else {
            throw CommandError.fixtureWAVReadFailed
        }
        guard WAVEncoder.validatePCM16Mono16kWAV(wavData) else {
            throw CommandError.invalidFixtureWAV
        }

        let loader = configLoader(parser: parser)
        let config = loader.load().resolvingSource(using: [:])
        let settings = SettingsStore.shared
        let model = parser.value(after: "--model").flatMap(AllowedSpeechModel.init(rawValue:)) ?? settings.selectedModel
        let selection = TranscriptionStyleSelection(rawValue: parser.value(after: "--style") ?? settings.transcriptionStyleSelection.rawValue)
        let descriptor = TranscriptionStyleResolver.resolve(
            selection: selection,
            customStyles: config.customStyles
        )
        let instruction = TranscriptionInstructionBuilder.instruction(descriptor: descriptor)
        let client = MimoAPIClient(config: config)
        return try await client.transcribe(
            wavData: wavData,
            model: model,
            instruction: instruction,
            onDelta: { _ in }
        )
    }

    private static func replayWAVData(parser: ArgumentParser) throws -> Data {
        guard let wavPath = parser.value(after: "--replay-wav")?.nilIfBlank else {
            throw CommandError.replayWAVReadFailed
        }
        let wavURL = URL(fileURLWithPath: wavPath)
        guard let wavData = try? Data(contentsOf: wavURL) else {
            throw CommandError.replayWAVReadFailed
        }
        guard WAVEncoder.validatePCM16Mono16kWAV(wavData) else {
            throw CommandError.invalidReplayWAV
        }
        return wavData
    }

    private static func replaySpeed(parser: ArgumentParser) throws -> Double {
        guard let raw = parser.value(after: "--replay-speed") else {
            return 1.0
        }
        guard let value = Double(raw), value.isFinite, value > 0 else {
            throw CommandError.invalidReplaySpeed
        }
        return value
    }

    private static func guiFrameIntervalSeconds(parser: ArgumentParser) -> Double {
        guard let raw = parser.value(after: "--gui-frame-interval-ms"),
              let value = Double(raw),
              value.isFinite,
              value > 0 else {
            return 1.0 / 12.0
        }
        return max(1.0 / 30.0, min(value / 1000.0, 1.0))
    }

    private static func uiLanguageValue(parser: ArgumentParser) -> UILanguage? {
        guard let raw = parser.value(after: "--ui-language")?.nilIfBlank else { return nil }
        switch raw.lowercased() {
        case "en", "english":
            return .english
        case "zh", "zh-hans", "chinese", "中文":
            return .chinese
        default:
            return UILanguage(rawValue: raw)
        }
    }

    private static func configLoader(parser: ArgumentParser) -> ConfigLoader {
        guard let path = parser.value(after: "--config-path")?.nilIfBlank else {
            return ConfigLoader()
        }
        return ConfigLoader(configFileURL: URL(fileURLWithPath: path))
    }

    @MainActor
    private static func artifactRecorder(parser: ArgumentParser) throws -> GUIArtifactRecorder? {
        guard let path = parser.value(after: "--gui-artifacts-dir")?.nilIfBlank else { return nil }
        return try GUIArtifactRecorder(directoryURL: URL(fileURLWithPath: path))
    }

    private static func activate(bundleIdentifier: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return false
        }
        return app.activate(options: [])
    }

    private static func writeJSON(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            print("{\"ok\":false,\"error\":\"json_encoding_failed\"}")
            return
        }
        print(string)
    }

    private static func jsonValue(_ value: Any?) -> Any {
        value ?? NSNull()
    }
}

private struct ArgumentParser {
    let arguments: [String]

    func has(_ flag: String) -> Bool {
        arguments.contains(flag)
    }

    func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        let value = arguments[valueIndex]
        guard !value.hasPrefix("--") else { return nil }
        return value
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
