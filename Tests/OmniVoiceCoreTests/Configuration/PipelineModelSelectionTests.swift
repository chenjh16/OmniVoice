import Testing
@testable import OmniVoiceCore

@Suite("Pipeline model selection")
struct PipelineModelSelectionTests {
    @Test
    func selectsAudioTextAndNoAPIModelsForPipelineModes() {
        let catalogs = ModelCatalogs(
            inputAudioDefaultModel: .mimoV25,
            inputAudioExtraModels: [.mimoV2Omni],
            textLLMDefaultModel: .mimoV25Pro
        )

        let audio = PipelineModelSelectionPlanner.selection(mode: .inputAudio, catalogs: catalogs)
        #expect(audio.selectedModel == .mimoV25)
        #expect(audio.modelCatalog == [.mimoV25, .mimoV2Omni])

        let text = PipelineModelSelectionPlanner.selection(mode: .systemASRTextLLM, catalogs: catalogs)
        #expect(text.selectedModel == .mimoV25Pro)
        #expect(text.modelCatalog == [.mimoV25Pro])

        let systemOnly = PipelineModelSelectionPlanner.selection(mode: .systemASROnly, catalogs: catalogs)
        #expect(systemOnly.selectedModel == .mimoV25)
        #expect(systemOnly.modelCatalog.isEmpty)
    }
}
