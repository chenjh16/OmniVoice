import AppKit
import Foundation
import OmniVoiceCore

enum InjectionE2ECommandError: String, Error {
    case missingTranscriptInput = "missing_transcript_input"
    case invalidFixtureWAV = "invalid_fixture_wav"
    case fixtureWAVReadFailed = "fixture_wav_read_failed"
    case replayWAVReadFailed = "replay_wav_read_failed"
    case invalidReplayWAV = "invalid_replay_wav"
    case invalidReplaySpeed = "invalid_replay_speed"
}

struct InjectionE2EArgumentParser {
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

    func values(after flag: String) -> [String] {
        var values: [String] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            guard arguments[index] == flag else {
                index = arguments.index(after: index)
                continue
            }
            let valueIndex = arguments.index(after: index)
            if valueIndex < arguments.endIndex {
                let value = arguments[valueIndex]
                if !value.hasPrefix("--"), let trimmed = value.nilIfBlank {
                    values.append(trimmed)
                }
                index = arguments.index(after: valueIndex)
            } else {
                index = valueIndex
            }
        }
        return values
    }
}

extension InjectionE2ECommand {
    static let usage = """
    OmniVoice injection E2E helper

    Usage:
      OmniVoice --omnivoice-injection-e2e --fixture-wav /tmp/sample.wav [--config-path /tmp/config.jsonc] [--style concise] [--model mimo-v2.5] [--target-bundle BUNDLE] [--expect-keyword WORD ...]
      OmniVoice --omnivoice-injection-e2e --replay-wav /tmp/sample.wav [--config-path /tmp/config.jsonc] [--style concise] [--model mimo-v2.5] [--hud-style darkCapsule] [--ui-language en] [--replay-speed 1.0] [--target-bundle BUNDLE] [--force-action-panel] [--gui-artifacts-dir DIR] [--record-gui-frames] [--gui-frame-interval-ms 83] [--expect-keyword WORD ...] [--output-json /tmp/result.json]
      OmniVoice --omnivoice-hud-preview-e2e [--hud-style darkCapsule] [--ui-language zh] [--preview-text TEXT] [--preview-badge TEXT] [--hold-ms 350] [--gui-artifacts-dir DIR]

    Notes:
      The JSON result is redacted: it includes character counts, keyword quality counts, strategy outcomes, bundle ids, and error classes, but never the transcript or clipboard contents.
      --fixture-wav is a fast transcription + injection helper. --replay-wav drives the recording HUD, RMS waveform, transcription HUD, streaming delta preview, and final injection path.
      --record-gui-frames samples OmniVoice HUD/ActionPanel surfaces into the GUI artifacts directory without using macOS screen recording.
      Mock transcription should be provided by an OpenAI-compatible local mock service and selected through --config-path.
    """

    static func uiLanguageValue(parser: InjectionE2EArgumentParser) -> UILanguage? {
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

    static func configLoader(parser: InjectionE2EArgumentParser) -> ConfigLoader {
        guard let path = parser.value(after: "--config-path")?.nilIfBlank else {
            return ConfigLoader()
        }
        return ConfigLoader(configFileURL: URL(fileURLWithPath: path))
    }

    @MainActor
    static func artifactRecorder(parser: InjectionE2EArgumentParser) throws -> GUIArtifactRecorder? {
        guard let path = parser.value(after: "--gui-artifacts-dir")?.nilIfBlank else { return nil }
        return try GUIArtifactRecorder(directoryURL: URL(fileURLWithPath: path))
    }

    static func activate(bundleIdentifier: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return false
        }
        return app.activate(options: [])
    }

    static func writeJSON(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            print("{\"ok\":false,\"error\":\"json_encoding_failed\"}")
            return
        }
        if let outputPath = InjectionE2EArgumentParser(arguments: CommandLine.arguments)
            .value(after: "--output-json")?.nilIfBlank {
            let url = URL(fileURLWithPath: outputPath)
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        print(string)
    }

    static func jsonValue(_ value: Any?) -> Any {
        value ?? NSNull()
    }

    static func addQualitySummary(_ quality: TranscriptQualitySummary, to result: inout [String: Any]) {
        result["final_text_chars"] = quality.finalTextCharacterCount
        result["quality_passed"] = quality.passed
        result["quality_expected_count"] = quality.expectedCount
        result["quality_matched_count"] = quality.matchedCount
        result["quality_missing_expected"] = quality.missingKeywords
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
