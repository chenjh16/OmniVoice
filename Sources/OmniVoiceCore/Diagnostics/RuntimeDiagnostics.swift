import Foundation
import OSLog

public struct RuntimeDiagnostic: Equatable, Sendable {
    public var timestamp: Date
    public var stage: String
    public var host: String
    public var model: String?
    public var recordingSeconds: Double?
    public var wavBytes: Int?
    public var rms: Float?
    public var httpStatus: Int?
    public var contentType: String?
    public var sseChunkCount: Int
    public var deltaCharacterCount: Int
    public var finishReason: String?
    public var cancellationState: String?
    public var insertionFallbackReason: String?
    public var errorKind: String?
    public var errorPreview: String?
    public var details: [String: String]

    public init(
        timestamp: Date = Date(),
        stage: String,
        host: String,
        model: String? = nil,
        recordingSeconds: Double? = nil,
        wavBytes: Int? = nil,
        rms: Float? = nil,
        httpStatus: Int? = nil,
        contentType: String? = nil,
        sseChunkCount: Int = 0,
        deltaCharacterCount: Int = 0,
        finishReason: String? = nil,
        cancellationState: String? = nil,
        insertionFallbackReason: String? = nil,
        errorKind: String? = nil,
        errorPreview: String? = nil,
        details: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.stage = stage
        self.host = host
        self.model = model
        self.recordingSeconds = recordingSeconds
        self.wavBytes = wavBytes
        self.rms = rms
        self.httpStatus = httpStatus
        self.contentType = contentType
        self.sseChunkCount = sseChunkCount
        self.deltaCharacterCount = deltaCharacterCount
        self.finishReason = finishReason
        self.cancellationState = cancellationState
        self.insertionFallbackReason = insertionFallbackReason
        self.errorKind = errorKind
        self.errorPreview = errorPreview.map(SecretRedactor.redact)
        self.details = details.mapValues(SecretRedactor.redact)
    }

    public var menuSummary: String {
        if let errorKind {
            return "\(stage): \(errorKind)"
        }
        if let finishReason {
            return "\(stage): completed (\(finishReason))"
        }
        return "\(stage): no errors"
    }

    public var clipboardText: String {
        var lines = [
            "\(AppConstants.productName) Diagnostics",
            "time: \(Self.isoFormatter.string(from: timestamp))",
            "stage: \(stage)",
            "host: \(host)"
        ]
        append("model", model, to: &lines)
        append("recording_seconds", recordingSeconds.map { String(format: "%.3f", $0) }, to: &lines)
        append("wav_bytes", wavBytes.map(String.init), to: &lines)
        append("rms", rms.map { String(format: "%.5f", $0) }, to: &lines)
        append("http_status", httpStatus.map(String.init), to: &lines)
        append("content_type", contentType, to: &lines)
        lines.append("sse_chunks: \(sseChunkCount)")
        lines.append("delta_chars: \(deltaCharacterCount)")
        append("finish_reason", finishReason, to: &lines)
        append("cancellation", cancellationState, to: &lines)
        append("insertion_fallback", insertionFallbackReason, to: &lines)
        append("error_kind", errorKind, to: &lines)
        append("error_preview", errorPreview, to: &lines)
        for key in details.keys.sorted() {
            append(key, details[key], to: &lines)
        }
        return SecretRedactor.redact(lines.joined(separator: "\n"))
    }

    public func withInsertionFallback(_ reason: String?) -> RuntimeDiagnostic {
        var copy = self
        copy.insertionFallbackReason = reason
        return copy
    }

    public static func log(_ diagnostic: RuntimeDiagnostic) {
        let text = diagnostic.clipboardText
        logger.info("\(text, privacy: .public)")
        writeToDiagnosticsFile(text)
    }

    private static let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "runtime")
    private static let fileQueue = DispatchQueue(label: "\(AppConstants.bundleIdentifier).diagnostics-log")
    public static let diagnosticsLogURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/\(AppConstants.logDirectoryName)/diagnostics.log")
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func writeToDiagnosticsFile(_ text: String) {
        fileQueue.async {
            do {
                let directory = diagnosticsLogURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let entry = text + "\n---\n"
                let data = Data(entry.utf8)
                if FileManager.default.fileExists(atPath: diagnosticsLogURL.path) {
                    let handle = try FileHandle(forWritingTo: diagnosticsLogURL)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: data)
                    try handle.close()
                } else {
                    try data.write(to: diagnosticsLogURL, options: [.atomic])
                }
            } catch {
                logger.error("Failed to write diagnostics log: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func append(_ key: String, _ value: String?, to lines: inout [String]) {
        guard let value, !value.isEmpty else { return }
        lines.append("\(key): \(SecretRedactor.redact(value))")
    }
}

public enum SecretRedactor {
    public static func redact(_ text: String) -> String {
        var output = text
        let patterns = [
            (#"(?i)(authorization:\s*bearer\s+)[A-Za-z0-9._~+/=-]+"#, "$1<redacted>"),
            (#"(?i)("?(api[_-]?key|token|secret|password)"?\s*[:=]\s*"?)[^"\s,}]+"#, "$1<redacted>"),
            (#"[A-Za-z0-9_\-]{32,}"#, "<redacted>")
        ]
        for (pattern, template) in patterns {
            output = replace(pattern: pattern, in: output, template: template)
        }
        return output
    }

    private static func replace(pattern: String, in text: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: template
        )
    }
}

public enum MenuTitleFormatter {
    public static func model(_ model: AllowedSpeechModel, uiLanguage: UILanguage = .english) -> String {
        UIStrings(language: uiLanguage).modelTitle(model)
    }

    public static func language(_ language: UILanguage, uiLanguage: UILanguage = .english) -> String {
        UIStrings(language: uiLanguage).uiLanguageTitle(language)
    }

    public static func style(_ style: TranscriptionStyle, uiLanguage: UILanguage = .english) -> String {
        UIStrings(language: uiLanguage).styleTitle(style)
    }

    public static func style(_ descriptor: TranscriptionStyleDescriptor, uiLanguage: UILanguage = .english) -> String {
        UIStrings(language: uiLanguage).styleTitle(descriptor)
    }

    public static func trigger(_ trigger: TriggerKey, uiLanguage: UILanguage = .english) -> String {
        UIStrings(language: uiLanguage).triggerTitle(trigger)
    }

    public static func maxDuration(_ duration: MaxRecordingDuration, uiLanguage: UILanguage = .english) -> String {
        UIStrings(language: uiLanguage).recordingDurationTitle(min: .defaultDuration, max: duration)
    }

    public static func recordingDuration(
        min: MinRecordingDuration,
        max: MaxRecordingDuration,
        uiLanguage: UILanguage = .english
    ) -> String {
        UIStrings(language: uiLanguage).recordingDurationTitle(min: min, max: max)
    }

    public static func hudStyle(_ style: HUDVisualStyle, uiLanguage: UILanguage = .english) -> String {
        UIStrings(language: uiLanguage).hudStyleTitle(style)
    }
}
