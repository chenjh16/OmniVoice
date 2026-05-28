import CryptoKit
import Foundation

public struct ASRSegmentAlternative: Equatable, Sendable {
    public let text: String
    public let alternatives: [String]
    public let confidence: Float

    public init(text: String, alternatives: [String], confidence: Float) {
        self.text = text
        self.alternatives = alternatives
        self.confidence = confidence
    }
}

public struct ASRRecognitionResult: Equatable, Sendable {
    public let text: String
    public let lowConfidenceSegments: [ASRSegmentAlternative]
    public let alternatives: [String]
    public let allowedAppleServerRecognition: Bool

    public init(
        text: String,
        lowConfidenceSegments: [ASRSegmentAlternative] = [],
        alternatives: [String] = [],
        allowedAppleServerRecognition: Bool = false
    ) {
        self.text = text
        self.lowConfidenceSegments = lowConfidenceSegments
        self.alternatives = alternatives
        self.allowedAppleServerRecognition = allowedAppleServerRecognition
    }
}

public struct SystemSpeechRecognitionOptions: Sendable {
    public let language: LanguagePreference
    public let engine: SystemASREngine
    public let keywordHints: KeywordHintsContext
    public let externalASRPlugin: ExternalASRPlugin?

    public init(
        language: LanguagePreference,
        engine: SystemASREngine,
        keywordHints: KeywordHintsContext,
        externalASRPlugin: ExternalASRPlugin? = nil
    ) {
        self.language = language
        self.engine = engine
        self.keywordHints = keywordHints
        self.externalASRPlugin = externalASRPlugin
    }
}

public struct LiveASRUpdate: Equatable, Sendable {
    public let text: String
    public let isFinal: Bool
    public let replacesCurrentSegment: Bool

    public init(
        text: String,
        isFinal: Bool,
        replacesCurrentSegment: Bool = false
    ) {
        self.text = text
        self.isFinal = isFinal
        self.replacesCurrentSegment = replacesCurrentSegment
    }
}

public protocol LiveSystemSpeechRecognitionSession: AnyObject, Sendable {
    func append(_ chunk: AudioSampleChunk)
    func finish() async throws -> ASRRecognitionResult
    func cancel()
}

public enum SystemSpeechRecognitionError: LocalizedError, Equatable, Sendable {
    case notAuthorized
    case recognizerUnavailable
    case speechAnalyzerUnavailable
    case onDeviceRecognitionUnavailable
    case noTextRecognized
    case temporaryFileFailed
    case recognitionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition permission is required"
        case .recognizerUnavailable:
            return "System speech recognition is unavailable"
        case .speechAnalyzerUnavailable:
            return "SpeechAnalyzer requires macOS 26 or later"
        case .onDeviceRecognitionUnavailable:
            return "On-device speech recognition is unavailable; Apple online recognition is off"
        case .noTextRecognized:
            return "No text recognized"
        case .temporaryFileFailed:
            return "Could not prepare audio for system speech recognition"
        case .recognitionFailed(let message):
            return message
        }
    }

    public var diagnosticKind: String {
        switch self {
        case .notAuthorized:
            return "speech_not_authorized"
        case .recognizerUnavailable:
            return "speech_recognizer_unavailable"
        case .speechAnalyzerUnavailable:
            return "speech_analyzer_unavailable"
        case .onDeviceRecognitionUnavailable:
            return "speech_on_device_unavailable"
        case .noTextRecognized:
            return "speech_no_text"
        case .temporaryFileFailed:
            return "speech_temp_file_failed"
        case .recognitionFailed:
            return "speech_recognition_failed"
        }
    }
}

public enum SystemASRKeywordPlanner {
    public static func contextualStrings(from context: KeywordHintsContext) -> [String] {
        guard context.isEnabled else { return [] }
        var seen = Set<String>()
        var output: [String] = []
        for group in context.activeGroups {
            for keyword in group.keywords {
                guard output.count < KeywordGroupValidator.maxASRContextualStrings,
                      let sanitized = KeywordGroupValidator.sanitizedKeyword(keyword),
                      sanitized.split(separator: " ").count <= 3,
                      !seen.contains(sanitized.lowercased()) else {
                    continue
                }
                seen.insert(sanitized.lowercased())
                output.append(sanitized)
            }
            if output.count >= KeywordGroupValidator.maxASRContextualStrings {
                break
            }
        }
        return output
    }
}

public enum SpeechAnalyzerAssetState: Equatable, Sendable {
    case unsupported
    case supported
    case downloading
    case installed
}

public enum SpeechAnalyzerPreflightAction: Equatable, Sendable {
    case unavailable
    case prepareAssets
    case ready
}

public enum SpeechAnalyzerPreflightPlanner {
    public static func action(for state: SpeechAnalyzerAssetState) -> SpeechAnalyzerPreflightAction {
        switch state {
        case .unsupported:
            return .unavailable
        case .supported, .downloading:
            return .prepareAssets
        case .installed:
            return .ready
        }
    }
}

public enum SystemASRCustomLanguageModelCacheKey {
    public static func version(localeIdentifier: String, keywords: [String]) -> String {
        let normalizedKeywords = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
            .sorted()
        let payload = ([localeIdentifier] + normalizedKeywords).joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum SystemASRFileRecognitionTimeoutPlanner {
    public static func timeoutSeconds(audioDurationSeconds: Double?) -> TimeInterval {
        guard let audioDurationSeconds,
              audioDurationSeconds.isFinite,
              audioDurationSeconds > 0 else {
            return 20
        }
        return min(max(20, audioDurationSeconds * 1.5 + 8), 180)
    }
}
