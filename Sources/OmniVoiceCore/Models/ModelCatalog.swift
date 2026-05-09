import Foundation

public struct AllowedSpeechModel: RawRepresentable, Hashable, Codable, Sendable, Comparable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard let value = rawValue.nilIfBlank,
              value.count <= 120,
              value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._:@/+~-]*$"#, options: .regularExpression) != nil else {
            return nil
        }
        self.rawValue = value
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let mimoV2Omni = AllowedSpeechModel("mimo-v2-omni")
    public static let mimoV25 = AllowedSpeechModel("mimo-v2.5")
    public static let mimoV2Pro = AllowedSpeechModel("mimo-v2-pro")
    public static let mimoV25Pro = AllowedSpeechModel("mimo-v2.5-pro")

    public static let builtinInputAudioModels: [AllowedSpeechModel] = [
        .mimoV25
    ]

    public static let seededInputAudioModels: [AllowedSpeechModel] = [
        .mimoV2Omni,
        "gpt-audio-1.5",
        "gpt-audio",
        "gpt-audio-2025-08-28",
        "gemini-3.1-pro-preview",
        "gemini-3.1-flash-lite",
        "gemini-2.5-pro",
        "gemini-2.5-flash",
        "gemini-2.5-flash-lite",
        "qwen3.5-omni-plus",
        "qwen3.5-omni-flash",
        "qwen3-omni-flash"
    ]

    public static let builtinTextLLMModels: [AllowedSpeechModel] = [
        .mimoV25
    ]

    public static let defaultInputAudioModel: AllowedSpeechModel = .mimoV25
    public static let defaultAudioLLMModel: AllowedSpeechModel = .defaultInputAudioModel
    public static let defaultTextLLMModel: AllowedSpeechModel = .mimoV25
    public static let defaultModel: AllowedSpeechModel = .defaultInputAudioModel
    public static let fallbackModel: AllowedSpeechModel = .mimoV25

    public static var allCases: [AllowedSpeechModel] {
        seededInputAudioCatalog()
    }

    public var displayName: String { rawValue }

    public static func < (lhs: AllowedSpeechModel, rhs: AllowedSpeechModel) -> Bool {
        lhs.rawValue.localizedStandardCompare(rhs.rawValue) == .orderedAscending
    }

    public static func catalog(inputAudioExtra: [AllowedSpeechModel]) -> [AllowedSpeechModel] {
        merged(builtinInputAudioModels + inputAudioExtra)
    }

    public static func seededInputAudioCatalog() -> [AllowedSpeechModel] {
        catalog(inputAudioExtra: seededInputAudioModels)
    }

    public static func filterSpeechModels(
        from ids: [String],
        catalog: [AllowedSpeechModel] = allCases
    ) -> [AllowedSpeechModel] {
        let available = Set(ids.filter { !$0.lowercased().contains("-tts") })
        return catalog.filter { available.contains($0.rawValue) }
    }

    public static func safeSelection(
        _ rawValue: String?,
        fallback: AllowedSpeechModel = .defaultModel,
        catalog: [AllowedSpeechModel]? = nil
    ) -> AllowedSpeechModel {
        guard let rawValue, let model = AllowedSpeechModel(rawValue: rawValue) else { return fallback }
        guard let catalog else { return model }
        return catalog.contains(model) ? model : fallback
    }

    public static func merged(_ models: [AllowedSpeechModel]) -> [AllowedSpeechModel] {
        var seen = Set<String>()
        var output: [AllowedSpeechModel] = []
        for model in models where !seen.contains(model.rawValue) {
            seen.insert(model.rawValue)
            output.append(model)
        }
        return output
    }
}

extension AllowedSpeechModel: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

public enum TranscriptionPipelineMode: String, CaseIterable, Codable, Sendable {
    case inputAudio = "input_audio"
    case systemASRTextLLM = "system_asr_text_llm"
    case systemASROnly = "system_asr_only"

    public static let defaultMode: TranscriptionPipelineMode = .inputAudio

    public var displayName: String {
        switch self {
        case .inputAudio: return "Direct Audio"
        case .systemASRTextLLM: return "Speech Recognition + Text Rewrite"
        case .systemASROnly: return "System ASR Only"
        }
    }

    public func displayName(in uiLanguage: UILanguage) -> String {
        switch (uiLanguage, self) {
        case (.chinese, .inputAudio): return "音频直转"
        case (.chinese, .systemASRTextLLM): return "语音识别 + 文本转写"
        case (.chinese, .systemASROnly): return "仅系统 ASR"
        case (.english, _): return displayName
        }
    }

    public var requiresModelAPI: Bool {
        self != .systemASROnly
    }

    public var usesSystemASR: Bool {
        self == .systemASRTextLLM || self == .systemASROnly
    }
}

public struct ModelCatalogs: Equatable, Sendable {
    public let inputAudioDefaultModel: AllowedSpeechModel
    public let inputAudioExtraModels: [AllowedSpeechModel]
    public let textLLMDefaultModel: AllowedSpeechModel

    public init(
        inputAudioDefaultModel: AllowedSpeechModel = .defaultAudioLLMModel,
        inputAudioExtraModels: [AllowedSpeechModel] = [],
        textLLMDefaultModel: AllowedSpeechModel = .defaultTextLLMModel
    ) {
        self.inputAudioDefaultModel = inputAudioDefaultModel
        self.inputAudioExtraModels = AllowedSpeechModel.merged(inputAudioExtraModels)
        self.textLLMDefaultModel = textLLMDefaultModel
    }

    public var inputAudioModels: [AllowedSpeechModel] {
        AllowedSpeechModel.merged([inputAudioDefaultModel] + AllowedSpeechModel.catalog(inputAudioExtra: inputAudioExtraModels))
    }

    public func with(
        inputAudioDefaultModel: AllowedSpeechModel? = nil,
        inputAudioExtraModels: [AllowedSpeechModel]? = nil,
        textLLMDefaultModel: AllowedSpeechModel? = nil
    ) -> ModelCatalogs {
        ModelCatalogs(
            inputAudioDefaultModel: inputAudioDefaultModel ?? self.inputAudioDefaultModel,
            inputAudioExtraModels: inputAudioExtraModels ?? self.inputAudioExtraModels,
            textLLMDefaultModel: textLLMDefaultModel ?? self.textLLMDefaultModel
        )
    }
}

extension ModelCatalogs {
    public static let defaultCatalogs = ModelCatalogs(
        inputAudioDefaultModel: .defaultAudioLLMModel,
        inputAudioExtraModels: AllowedSpeechModel.seededInputAudioModels,
        textLLMDefaultModel: .defaultTextLLMModel
    )
}

public struct ModelAvailabilityIndex: Equatable, Sendable {
    public let sourceModelIDs: [String: Set<String>]
    public let reachableSourceIDs: Set<String>
    public let catalogs: ModelCatalogs

    public init(
        measurements: [String: SourceLatencyMeasurement],
        catalogs: ModelCatalogs
    ) {
        var sourceModelIDs: [String: Set<String>] = [:]
        var reachableSourceIDs = Set<String>()
        for (sourceID, measurement) in measurements {
            guard measurement.reachable,
                  let status = measurement.httpStatus,
                  (200..<300).contains(status) else {
                continue
            }
            reachableSourceIDs.insert(sourceID)
            sourceModelIDs[sourceID] = Set(measurement.allowedModelIDs)
        }
        self.sourceModelIDs = sourceModelIDs
        self.reachableSourceIDs = reachableSourceIDs
        self.catalogs = catalogs
    }

    public var hasMeasurements: Bool {
        !sourceModelIDs.isEmpty
    }

    public func availableModels(for mode: TranscriptionPipelineMode) -> [AllowedSpeechModel] {
        let observed = Set(sourceModelIDs.values.flatMap { $0 })
        switch mode {
        case .systemASRTextLLM:
            return observed
                .compactMap(AllowedSpeechModel.init(rawValue:))
                .filter { !ModelCapabilityHeuristics.isClearlyNonTextCompletionModel($0) }
                .sorted()
        case .systemASROnly:
            return []
        case .inputAudio:
            return catalogs.inputAudioModels.filter { model in
                observed.contains(model.rawValue) && !ModelCapabilityHeuristics.isClearlyAudioGenerationModel(model)
            }
        }
    }

    public func sourceIDsSupporting(
        _ model: AllowedSpeechModel,
        mode: TranscriptionPipelineMode
    ) -> [String] {
        guard mode.requiresModelAPI else { return [] }
        if mode == .inputAudio, ModelCapabilityHeuristics.isClearlyAudioGenerationModel(model) {
            return []
        }
        if mode == .systemASRTextLLM, ModelCapabilityHeuristics.isClearlyNonTextCompletionModel(model) {
            return []
        }
        return sourceModelIDs
            .filter { _, modelIDs in modelIDs.contains(model.rawValue) }
            .map(\.key)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public func sourceSupports(
        _ sourceID: String,
        model: AllowedSpeechModel,
        mode: TranscriptionPipelineMode
    ) -> Bool {
        sourceIDsSupporting(model, mode: mode).contains(sourceID)
    }
}

public enum SourceLatencyRefreshPlanner {
    public static func mergedMeasurements(
        existing: [String: SourceLatencyMeasurement],
        refreshed: [String: SourceLatencyMeasurement],
        configuredSourceIDs: [String]
    ) -> [String: SourceLatencyMeasurement] {
        let configured = Set(configuredSourceIDs)
        var output = existing.filter { configured.contains($0.key) }
        for sourceID in configuredSourceIDs {
            if let measurement = refreshed[sourceID] {
                output[sourceID] = measurement
            }
        }
        return output
    }
}

public enum ModelCapabilityHeuristics {
    public static func isClearlyAudioGenerationModel(_ model: AllowedSpeechModel) -> Bool {
        let id = model.rawValue.lowercased()
        return id.contains("tts") ||
            id.contains("voiceclone") ||
            id.contains("voicedesign")
    }

    public static func isClearlyNonTextCompletionModel(_ model: AllowedSpeechModel) -> Bool {
        isClearlyAudioGenerationModel(model)
    }
}

public enum ModelRequestProfile: String, Codable, Sendable {
    case mimoInputAudio = "mimo_input_audio"
    case openAIInputAudio = "openai_input_audio"
    case geminiOpenAIInputAudio = "gemini_openai_input_audio"
    case qwenOmniInputAudio = "qwen_omni_input_audio"
    case openAITextChat = "openai_text_chat"

    public static func inputAudioProfile(for model: AllowedSpeechModel) -> ModelRequestProfile {
        let id = model.rawValue.lowercased()
        if id.hasPrefix("mimo-") { return .mimoInputAudio }
        if id.hasPrefix("gemini-") { return .geminiOpenAIInputAudio }
        if id.hasPrefix("qwen") { return .qwenOmniInputAudio }
        return .openAIInputAudio
    }

    public static func textProfile(for model: AllowedSpeechModel) -> ModelRequestProfile {
        model.rawValue.lowercased().hasPrefix("mimo-") ? .mimoInputAudio : .openAITextChat
    }

    public var sendsMimoThinkingDisabled: Bool {
        self == .mimoInputAudio
    }

    public var sendsTextModalities: Bool {
        self == .qwenOmniInputAudio
    }
}
