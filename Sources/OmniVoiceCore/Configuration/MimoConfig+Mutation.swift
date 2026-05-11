import Foundation

extension MimoConfig {
    func updating(
        baseURL: URL? = nil,
        apiKey: String?? = nil,
        source: ConfigSource? = nil,
        activeSourceID: String? = nil,
        resolvedSourceID: String? = nil,
        sources: [MimoConfigSource]? = nil,
        modelCatalogs: ModelCatalogs? = nil,
        pipelineMode: TranscriptionPipelineMode? = nil,
        systemASRSettings: SystemASRSettings? = nil,
        customStyles: [CustomTranscriptionStyle]? = nil,
        keywordGroups: [KeywordGroup]? = nil,
        latencySettings: ConfigLatencySettings? = nil,
        preferences: ConfigPreferences? = nil,
        warnings: [String]? = nil
    ) -> MimoConfig {
        MimoConfig(
            baseURL: baseURL ?? self.baseURL,
            apiKey: apiKey ?? self.apiKey,
            source: source ?? self.source,
            activeSourceID: activeSourceID ?? self.activeSourceID,
            resolvedSourceID: resolvedSourceID ?? self.resolvedSourceID,
            sources: sources ?? self.sources,
            modelCatalogs: modelCatalogs ?? self.modelCatalogs,
            pipelineMode: pipelineMode ?? self.pipelineMode,
            systemASRSettings: systemASRSettings ?? self.systemASRSettings,
            customStyles: customStyles ?? self.customStyles,
            keywordGroups: keywordGroups ?? self.keywordGroups,
            latencySettings: latencySettings ?? self.latencySettings,
            preferences: preferences ?? self.preferences,
            warnings: warnings ?? self.warnings
        )
    }
}
