import Foundation

struct SourceLatencyRefreshOutput: Sendable {
    let orderedResults: [(source: MimoConfigSource, measurement: SourceLatencyMeasurement)]
    let mergedMeasurements: [String: SourceLatencyMeasurement]
    let resolvedConfig: MimoConfig
}

enum SourceLatencyCoordinator {
    static func refresh(
        config: MimoConfig,
        existingMeasurements: [String: SourceLatencyMeasurement]
    ) async -> SourceLatencyRefreshOutput {
        let sourceJobs = config.sources.compactMap { source -> (source: MimoConfigSource, config: MimoConfig)? in
            guard let sourceConfig = config.selectingSource(source.id) else { return nil }
            return (source, sourceConfig)
        }
        let sourceOrder = Dictionary(uniqueKeysWithValues: sourceJobs.enumerated().map { ($0.element.source.id, $0.offset) })
        let orderedResults = await withTaskGroup(
            of: (source: MimoConfigSource, measurement: SourceLatencyMeasurement).self,
            returning: [(source: MimoConfigSource, measurement: SourceLatencyMeasurement)].self
        ) { group in
            for job in sourceJobs {
                group.addTask {
                    let measurement = await MimoAPIClient(config: job.config).measureModelsLatency()
                    return (job.source, measurement)
                }
            }
            var results: [(source: MimoConfigSource, measurement: SourceLatencyMeasurement)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { lhs, rhs in
                (sourceOrder[lhs.source.id] ?? Int.max) < (sourceOrder[rhs.source.id] ?? Int.max)
            }
        }
        let measurements = Dictionary(uniqueKeysWithValues: orderedResults.map { ($0.source.id, $0.measurement) })
        let mergedMeasurements = SourceLatencyRefreshPlanner.mergedMeasurements(
            existing: existingMeasurements,
            refreshed: measurements,
            configuredSourceIDs: config.sources.map(\.id)
        )
        return SourceLatencyRefreshOutput(
            orderedResults: orderedResults,
            mergedMeasurements: mergedMeasurements,
            resolvedConfig: config.resolvingSource(using: mergedMeasurements)
        )
    }
}
