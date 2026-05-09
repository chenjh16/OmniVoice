import Foundation

public struct TranscriptionProgressEstimator: Sendable {
    public let recordingSeconds: Double
    public let estimatedProcessingSeconds: Double

    public init(recordingSeconds: Double) {
        self.recordingSeconds = max(0, recordingSeconds)
        self.estimatedProcessingSeconds = Self.estimatedProcessingSeconds(for: recordingSeconds)
    }

    public static func estimatedProcessingSeconds(for recordingSeconds: Double) -> Double {
        min(max(2 + max(0, recordingSeconds) * 0.6, 3), 45)
    }

    public func progress(
        elapsedSeconds: Double,
        hasReceivedDelta: Bool,
        isFinished: Bool,
        deltaChunkCount: Int = 0,
        deltaCharacterCount: Int = 0
    ) -> Double {
        if isFinished { return 1.0 }
        guard estimatedProcessingSeconds > 0 else { return 0 }

        let elapsedRatio = min(max(elapsedSeconds / estimatedProcessingSeconds, 0), 1)
        if hasReceivedDelta {
            let deltaBoost = min(0.32, Double(max(deltaChunkCount, 1)) * 0.035 + Double(max(deltaCharacterCount, 1)) * 0.0012)
            let timeBoost = min(0.12, elapsedRatio * 0.12)
            return min(max(0.50 + deltaBoost + timeBoost, 0.50), 0.95)
        }

        return min(elapsedRatio * 0.82, 0.88)
    }
}
