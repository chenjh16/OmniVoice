import Foundation

enum ConfigTemplateBuilder {
    static func template(uiLanguage: UILanguage) -> String {
        ConfigDocumentWriter.defaultDocument(uiLanguage: uiLanguage)
    }
}

public struct ConfigRedactedStatus: Equatable, Sendable {
    public let baseURLHost: String
    public let apiKeyConfigured: Bool
    public let apiKeyPreview: String
    public let source: ConfigSource
    public let activeSourceID: String
    public let resolvedSourceID: String
    public let inputAudioModel: AllowedSpeechModel
    public let textLLMModel: AllowedSpeechModel
    public let pipelineMode: TranscriptionPipelineMode
    public let warnings: [String]

    public var displayLines: [String] {
        var lines = [
            "Source: \(activeSourceID)",
            "Base URL: \(baseURLHost)",
            "API Key: \(apiKeyPreview)",
            "Input Audio Model: \(inputAudioModel.rawValue)",
            "Text LLM Model: \(textLLMModel.rawValue)",
            "Transcription Mode: \(pipelineMode.rawValue)",
            "Config Source: \(source.displayName)"
        ]
        lines.append(contentsOf: warnings)
        return lines
    }
}

public enum ConfigValidationLoadResult: Equatable, Sendable {
    case valid(MimoConfig)
    case invalid([String])
}
