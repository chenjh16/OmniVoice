import Foundation

public enum MimoAPIError: LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case invalidWAV
    case invalidResponse
    case httpStatus(Int, String?)
    case authenticationFailed(String?)
    case modelDoesNotSupportAudio(String?)
    case modelDoesNotSupportText(Int?, String?)
    case malformedSSE(String?)
    case serverError(String)
    case streamEndedBeforeCompletion
    case noDeltaContent
    case emptyFinalText
    case networkFailure(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API Key missing"
        case .invalidWAV:
            return "Invalid WAV"
        case .invalidResponse:
            return "Invalid response"
        case .httpStatus(let status, let preview):
            return preview.map { "HTTP \(status): \($0)" } ?? "HTTP \(status)"
        case .authenticationFailed:
            return "Authentication failed"
        case .modelDoesNotSupportAudio:
            return "Model does not support audio"
        case .modelDoesNotSupportText(_, _):
            return "Model may not support text completion"
        case .malformedSSE(let preview):
            return preview.map { "Malformed stream: \($0)" } ?? "Malformed stream"
        case .serverError(let message):
            return message
        case .streamEndedBeforeCompletion:
            return "Stream interrupted"
        case .noDeltaContent:
            return "No transcription delta"
        case .emptyFinalText:
            return "Empty transcription"
        case .networkFailure(let message):
            return message
        case .cancelled:
            return "Cancelled"
        }
    }

    public var diagnosticKind: String {
        switch self {
        case .missingAPIKey: return "missing_api_key"
        case .invalidWAV: return "invalid_wav"
        case .invalidResponse: return "invalid_response"
        case .httpStatus(let status, _): return "http_\(status)"
        case .authenticationFailed: return "authentication_failed"
        case .modelDoesNotSupportAudio: return "model_or_audio_unsupported"
        case .modelDoesNotSupportText(_, _): return "text_model_unsupported"
        case .malformedSSE: return "malformed_sse"
        case .serverError: return "server_error"
        case .streamEndedBeforeCompletion: return "stream_ended_before_completion"
        case .noDeltaContent: return "no_delta_content"
        case .emptyFinalText: return "empty_final_text"
        case .networkFailure: return "network_failure"
        case .cancelled: return "cancelled"
        }
    }

    public var diagnosticPreview: String? {
        switch self {
        case .httpStatus(_, let preview),
             .authenticationFailed(let preview),
             .modelDoesNotSupportAudio(let preview),
             .modelDoesNotSupportText(_, let preview),
             .malformedSSE(let preview):
            return preview
        case .serverError(let message), .networkFailure(let message):
            return message
        default:
            return nil
        }
    }

    public static func classifiedHTTP(status: Int, preview: String?) -> MimoAPIError {
        switch status {
        case 401, 403:
            return .authenticationFailed(preview)
        case 400, 404, 415, 422:
            return .modelDoesNotSupportAudio(preview)
        default:
            return .httpStatus(status, preview)
        }
    }

    public static func classifiedTextCompletionHTTP(status: Int, preview: String?) -> MimoAPIError {
        switch status {
        case 401, 403:
            return .authenticationFailed(preview)
        case 400, 404, 415, 422:
            return .modelDoesNotSupportText(status, preview)
        default:
            return .httpStatus(status, preview)
        }
    }
}

public enum TextLLMFailureClassifier {
    private static let unsupportedTextPatterns = [
        "model does not support",
        "unsupported model",
        "not support chat",
        "does not support chat",
        "not support text",
        "does not support text",
        "not found",
        "invalid model",
        "chat completions",
        "chat completion"
    ]

    public static func isLikelyUnsupportedTextModel(_ error: Error) -> Bool {
        guard let mimoError = error as? MimoAPIError else { return false }
        switch mimoError {
        case .modelDoesNotSupportText(_, _):
            return true
        case .httpStatus(let status, let preview):
            return [400, 404, 415, 422].contains(status) && containsUnsupportedTextPattern(preview)
        case .serverError(let message), .networkFailure(let message):
            return containsUnsupportedTextPattern(message)
        default:
            return containsUnsupportedTextPattern(mimoError.diagnosticPreview)
        }
    }

    public static func classifiedServerError(_ message: String) -> MimoAPIError {
        containsUnsupportedTextPattern(message)
            ? .modelDoesNotSupportText(nil, message)
            : .serverError(message)
    }

    private static func containsUnsupportedTextPattern(_ value: String?) -> Bool {
        guard let value else { return false }
        let normalized = value.lowercased()
        return unsupportedTextPatterns.contains { normalized.contains($0) }
    }
}

public struct TestConnectionResult: Equatable, Sendable {
    public let selectedModel: String
    public let modelsReachable: Bool
    public let selectedModelAllowed: Bool
    public let audioProbeAccepted: Bool?
    public let audioProbeError: String?
    public let message: String

    public init(
        selectedModel: String,
        modelsReachable: Bool,
        selectedModelAllowed: Bool,
        audioProbeAccepted: Bool?,
        audioProbeError: String? = nil,
        message: String
    ) {
        self.selectedModel = selectedModel
        self.modelsReachable = modelsReachable
        self.selectedModelAllowed = selectedModelAllowed
        self.audioProbeAccepted = audioProbeAccepted
        self.audioProbeError = audioProbeError
        self.message = message
    }
}

public struct SourceLatencyMeasurement: Equatable, Sendable {
    public let milliseconds: Int?
    public let httpStatus: Int?
    public let reachable: Bool
    public let allowedModelIDs: [String]
    public let measuredAt: Date
    public let errorKind: String?

    public init(
        milliseconds: Int?,
        httpStatus: Int?,
        reachable: Bool,
        allowedModelIDs: [String] = [],
        measuredAt: Date = Date(),
        errorKind: String? = nil
    ) {
        self.milliseconds = milliseconds
        self.httpStatus = httpStatus
        self.reachable = reachable
        self.allowedModelIDs = allowedModelIDs
        self.measuredAt = measuredAt
        self.errorKind = errorKind
    }

    public var allowedSpeechModels: [AllowedSpeechModel] {
        AllowedSpeechModel.filterSpeechModels(from: allowedModelIDs)
    }

    public func allowedSpeechModels(in catalog: [AllowedSpeechModel]) -> [AllowedSpeechModel] {
        AllowedSpeechModel.filterSpeechModels(from: allowedModelIDs, catalog: catalog)
    }

    public var hasAllowedSpeechModel: Bool {
        !allowedSpeechModels.isEmpty
    }

    public var isAutoEligible: Bool {
        guard let httpStatus, (200..<300).contains(httpStatus) else { return false }
        return hasAllowedSpeechModel
    }
}

public enum AudioProbeSupport {
    public static func accepts(error: Error) -> Bool {
        guard let error = error as? MimoAPIError else { return false }
        switch error {
        case .noDeltaContent, .emptyFinalText:
            return true
        default:
            return false
        }
    }
}

public protocol TranscriptionClient: Sendable {
    func fetchModels() async throws -> [String]
    func measureModelsLatency(timeout: TimeInterval) async -> SourceLatencyMeasurement
    func testConnection(selectedModel: AllowedSpeechModel, runAudioProbe: Bool) async -> TestConnectionResult
    func transcribe(
        wavData: Data,
        model: AllowedSpeechModel,
        instruction: String,
        recordingSeconds: Double?,
        overallRMS: Float?,
        allowEmptyFinalText: Bool,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String
    func completeText(
        model: AllowedSpeechModel,
        instruction: String,
        allowEmptyFinalText: Bool,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> String
}

extension Data {
    func redactedPreview(limit: Int = 800) -> String? {
        guard !isEmpty else { return nil }
        let previewData = prefix(limit)
        let text = String(data: previewData, encoding: .utf8) ?? previewData.base64EncodedString()
        return SecretRedactor.redact(text)
    }
}
