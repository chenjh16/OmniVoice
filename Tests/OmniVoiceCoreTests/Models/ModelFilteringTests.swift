import Foundation
import ApplicationServices
import Testing
@testable import OmniVoiceCore

@Suite("Model filtering")
struct ModelFilteringTests {
    @Test
    func modelFilteringAllowsOnlySpeechModels() {
        let ids = [
            "mimo-v2-omni",
            "mimo-v2.5",
            "mimo-v2-pro",
            "mimo-v2.5-pro",
            "mimo-v2-tts",
            "mimo-v2.5-tts",
            "mimo-v2.5-tts-voiceclone",
            "mimo-v2.5-tts-voicedesign"
        ]
        #expect(AllowedSpeechModel.filterSpeechModels(from: ids).map(\.rawValue) == ["mimo-v2.5", "mimo-v2-omni"])
    }

    @Test
    func sourceLatencyRefreshMergePrunesStaleSourcesAndAppliesNewMeasurements() {
        let oldCN = SourceLatencyMeasurement(
            milliseconds: 300,
            httpStatus: 200,
            reachable: true,
            allowedModelIDs: ["mimo-v2-omni"]
        )
        let newCN = SourceLatencyMeasurement(
            milliseconds: 80,
            httpStatus: 200,
            reachable: true,
            allowedModelIDs: ["mimo-v2.5"]
        )
        let sgp = SourceLatencyMeasurement(
            milliseconds: 120,
            httpStatus: 200,
            reachable: true,
            allowedModelIDs: ["mimo-v2.5", "gpt-5.5"]
        )
        let stale = SourceLatencyMeasurement(
            milliseconds: 10,
            httpStatus: 200,
            reachable: true,
            allowedModelIDs: ["stale-model"]
        )

        let merged = SourceLatencyRefreshPlanner.mergedMeasurements(
            existing: ["cn": oldCN, "old": stale],
            refreshed: ["cn": newCN, "sgp": sgp],
            configuredSourceIDs: ["sgp", "cn"]
        )

        #expect(Set(merged.keys) == Set(["sgp", "cn"]))
        #expect(merged["cn"] == newCN)
        #expect(merged["sgp"] == sgp)
    }
}
