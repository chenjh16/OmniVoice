import Foundation

public enum APISourceResolver {
    public static func resolvedSource(
        activeSourceID: String,
        sources: [MimoConfigSource],
        latencyResults: [String: SourceLatencyMeasurement],
        modelCatalog: [AllowedSpeechModel] = AllowedSpeechModel.allCases,
        requiredModel: AllowedSpeechModel? = nil,
        mode: TranscriptionPipelineMode = .inputAudio
    ) -> MimoConfigSource? {
        guard mode.requiresModelAPI else { return nil }
        guard !sources.isEmpty else { return nil }
        let activeID = activeSourceID.nilIfBlank ?? MimoConfig.defaultSourceID
        guard activeID == MimoConfig.autoSourceID else {
            let selected = sources.first(where: { $0.id == activeID }) ?? sources.first
            guard let selected,
                  let requiredModel,
                  let measurement = latencyResults[selected.id] else {
                return selected
            }
            if sourceSupportsModel(measurement, model: requiredModel, catalog: modelCatalog, mode: mode) {
                return selected
            }
            return eligibleSources(
                sources: sources,
                latencyResults: latencyResults,
                modelCatalog: modelCatalog,
                requiredModel: requiredModel,
                mode: mode
            ).first?.source ?? selected
        }

        return eligibleSources(
            sources: sources,
            latencyResults: latencyResults,
            modelCatalog: modelCatalog,
            requiredModel: requiredModel,
            mode: mode
        ).first?.source ?? sources.first
    }

    private static func eligibleSources(
        sources: [MimoConfigSource],
        latencyResults: [String: SourceLatencyMeasurement],
        modelCatalog: [AllowedSpeechModel],
        requiredModel: AllowedSpeechModel?,
        mode: TranscriptionPipelineMode
    ) -> [(source: MimoConfigSource, measurement: SourceLatencyMeasurement)] {
        sources.compactMap { source -> (source: MimoConfigSource, measurement: SourceLatencyMeasurement)? in
            guard let measurement = latencyResults[source.id],
                  sourceSupportsModel(measurement, model: requiredModel, catalog: modelCatalog, mode: mode) else { return nil }
            return (source, measurement)
        }.sorted {
            let leftMS = $0.measurement.milliseconds ?? Int.max
            let rightMS = $1.measurement.milliseconds ?? Int.max
            if leftMS != rightMS {
                return leftMS < rightMS
            }
            return $0.source.id.localizedStandardCompare($1.source.id) == .orderedAscending
        }
    }

    private static func sourceSupportsModel(
        _ measurement: SourceLatencyMeasurement,
        model requiredModel: AllowedSpeechModel?,
        catalog: [AllowedSpeechModel],
        mode: TranscriptionPipelineMode
    ) -> Bool {
        guard measurement.reachable,
              let httpStatus = measurement.httpStatus,
              (200..<300).contains(httpStatus) else {
            return false
        }
        guard let requiredModel else {
            if mode == .systemASRTextLLM {
                return !measurement.allowedModelIDs
                    .compactMap(AllowedSpeechModel.init(rawValue:))
                    .filter { !ModelCapabilityHeuristics.isClearlyNonTextCompletionModel($0) }
                    .isEmpty
            }
            return !AllowedSpeechModel.filterSpeechModels(from: measurement.allowedModelIDs, catalog: catalog).isEmpty
        }
        if mode == .systemASRTextLLM {
            return !ModelCapabilityHeuristics.isClearlyNonTextCompletionModel(requiredModel) &&
                measurement.allowedModelIDs.contains(requiredModel.rawValue)
        }
        guard catalog.contains(requiredModel),
              measurement.allowedModelIDs.contains(requiredModel.rawValue) else {
            return false
        }
        return !ModelCapabilityHeuristics.isClearlyAudioGenerationModel(requiredModel)
    }
}
