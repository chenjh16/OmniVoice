import AppKit
import Foundation
import OmniVoiceCore

extension InjectionE2ECommand {
    @MainActor
    static func runReplay(
        parser: InjectionE2EArgumentParser,
        startedAt: Date,
        initialResult: [String: Any]
    ) async -> Int {
        var result = initialResult
        result["mode"] = "recording_replay_e2e"

        do {
            let wavData = try replayWAVData(parser: parser)
            let speed = try replaySpeed(parser: parser)
            let hudVisualStyle = parser.value(after: "--hud-style").map(HUDVisualStyle.safeSelection)
            let uiLanguage = uiLanguageValue(parser: parser)
            let expectedKeywords = parser.values(after: "--expect-keyword")
            let loader = configLoader(parser: parser)
            let configStore = AppConfigStore(loader: loader)
            let config = configStore.config.resolvingSource(using: [:])
            let model = parser.value(after: "--model").flatMap(AllowedSpeechModel.init(rawValue:))
                ?? config.modelCatalogs.inputAudioDefaultModel
            let styleSelection = TranscriptionStyleSelection(
                rawValue: parser.value(after: "--style") ?? config.preferences.transcriptionStyleSelection.rawValue
            )
            let artifactRecorder = try artifactRecorder(parser: parser)
            let forceActionPanel = parser.has("--force-action-panel")
            let recordGUIFrames = parser.has("--record-gui-frames")
            let guiFrameIntervalSeconds = guiFrameIntervalSeconds(parser: parser)

            result["model"] = model.rawValue
            result["style"] = styleSelection.rawValue
            result["hud_style"] = hudVisualStyle?.rawValue ?? config.preferences.hudVisualStyle.rawValue
            result["ui_language"] = uiLanguage?.rawValue ?? config.preferences.uiLanguage.rawValue
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
                    expectedKeywords: expectedKeywords,
                    forceAutoInsert: !forceActionPanel,
                    forceActionPanel: forceActionPanel,
                    targetBundleIdentifier: parser.value(after: "--target-bundle"),
                    hudVisualStyle: hudVisualStyle,
                    uiLanguage: uiLanguage,
                    recordGUIFrames: recordGUIFrames,
                    guiFrameIntervalSeconds: guiFrameIntervalSeconds
                )
            )

            if let quality = automation.qualitySummary {
                addQualitySummary(quality, to: &result)
            }
            let qualityPassed = automation.qualitySummary?.passed ?? true
            result["ok"] = automation.ok && qualityPassed
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
            if automation.ok && qualityPassed {
                return 0
            }
            if automation.ok && !qualityPassed {
                return 3
            }
            if automation.injectionResult == "fallback" {
                return 2
            }
            return 1
        } catch let error as InjectionE2ECommandError {
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

    static func replayWAVData(parser: InjectionE2EArgumentParser) throws -> Data {
        guard let wavPath = parser.value(after: "--replay-wav")?.nilIfBlank else {
            throw InjectionE2ECommandError.replayWAVReadFailed
        }
        let wavURL = URL(fileURLWithPath: wavPath)
        guard let wavData = try? Data(contentsOf: wavURL) else {
            throw InjectionE2ECommandError.replayWAVReadFailed
        }
        guard WAVEncoder.validatePCM16Mono16kWAV(wavData) else {
            throw InjectionE2ECommandError.invalidReplayWAV
        }
        return wavData
    }

    static func replaySpeed(parser: InjectionE2EArgumentParser) throws -> Double {
        guard let raw = parser.value(after: "--replay-speed") else {
            return 1.0
        }
        guard let value = Double(raw), value.isFinite, value > 0 else {
            throw InjectionE2ECommandError.invalidReplaySpeed
        }
        return value
    }

    static func guiFrameIntervalSeconds(parser: InjectionE2EArgumentParser) -> Double {
        guard let raw = parser.value(after: "--gui-frame-interval-ms"),
              let value = Double(raw),
              value.isFinite,
              value > 0 else {
            return 1.0 / 12.0
        }
        return max(1.0 / 30.0, min(value / 1000.0, 1.0))
    }
}
