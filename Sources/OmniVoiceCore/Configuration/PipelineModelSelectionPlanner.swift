import Foundation

struct PipelineModelSelection: Equatable, Sendable {
    let selectedModel: AllowedSpeechModel
    let modelCatalog: [AllowedSpeechModel]
}

enum PipelineModelSelectionPlanner {
    static func selection(
        mode: TranscriptionPipelineMode,
        catalogs: ModelCatalogs,
        inputAudioModel: AllowedSpeechModel? = nil,
        textLLMModel: AllowedSpeechModel? = nil
    ) -> PipelineModelSelection {
        let audioModel = inputAudioModel ?? catalogs.inputAudioDefaultModel
        let textModel = textLLMModel ?? catalogs.textLLMDefaultModel
        switch mode {
        case .inputAudio:
            return PipelineModelSelection(
                selectedModel: audioModel,
                modelCatalog: catalogs.with(inputAudioDefaultModel: audioModel).inputAudioModels
            )
        case .systemASRTextLLM:
            return PipelineModelSelection(
                selectedModel: textModel,
                modelCatalog: [textModel]
            )
        case .systemASROnly:
            return PipelineModelSelection(
                selectedModel: audioModel,
                modelCatalog: []
            )
        }
    }
}
