import Foundation

public enum MaxRecordingDuration: Int, CaseIterable, Codable, Sendable {
    case seconds15 = 15
    case seconds30 = 30
    case seconds60 = 60
    case seconds120 = 120
    case seconds300 = 300

    public static let defaultDuration: MaxRecordingDuration = .seconds120

    public var displayName: String { "\(rawValue)s" }

    public static func safeSelection(_ seconds: Int) -> MaxRecordingDuration {
        MaxRecordingDuration(rawValue: seconds) ?? .defaultDuration
    }
}

public enum MinRecordingDuration: Int, CaseIterable, Codable, Sendable {
    case milliseconds300 = 300
    case milliseconds500 = 500
    case milliseconds800 = 800
    case seconds1 = 1_000
    case seconds2 = 2_000
    case seconds3 = 3_000

    public static let defaultDuration: MinRecordingDuration = .milliseconds500

    public var seconds: Double {
        Double(rawValue) / 1_000
    }

    public var displayName: String {
        switch self {
        case .milliseconds300: return "300ms"
        case .milliseconds500: return "500ms"
        case .milliseconds800: return "800ms"
        case .seconds1: return "1s"
        case .seconds2: return "2s"
        case .seconds3: return "3s"
        }
    }

    public static func safeSelection(_ milliseconds: Int) -> MinRecordingDuration {
        MinRecordingDuration(rawValue: milliseconds) ?? .defaultDuration
    }
}

public struct RecordingValidationResult: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case valid
        case tooShort
        case tooQuiet
    }

    public let status: Status
    public let durationSeconds: Double
    public let overallRMS: Float

    public init(status: Status, durationSeconds: Double, overallRMS: Float) {
        self.status = status
        self.durationSeconds = durationSeconds
        self.overallRMS = overallRMS
    }
}

public enum RecordingValidationPolicy: String, Equatable, Sendable {
    case voiceGated = "voice_gated"
    case durationOnly = "duration_only"
}

public enum RecordingValidationPolicyResolver {
    public static func policy(for mode: TranscriptionPipelineMode) -> RecordingValidationPolicy {
        switch mode {
        case .inputAudio:
            return .voiceGated
        case .systemASRTextLLM, .systemASROnly:
            return .durationOnly
        }
    }
}

public enum RecordingValidator {
    public static let minimumDurationSeconds = MinRecordingDuration.defaultDuration.seconds
    public static let minimumEffectiveRMS: Float = 0.008

    public static func validate(
        durationSeconds: Double,
        overallRMS: Float,
        minimumDurationSeconds: Double = minimumDurationSeconds,
        policy: RecordingValidationPolicy = .voiceGated
    ) -> RecordingValidationResult {
        if durationSeconds < minimumDurationSeconds {
            return RecordingValidationResult(status: .tooShort, durationSeconds: durationSeconds, overallRMS: overallRMS)
        }
        if policy == .voiceGated, overallRMS < minimumEffectiveRMS {
            return RecordingValidationResult(status: .tooQuiet, durationSeconds: durationSeconds, overallRMS: overallRMS)
        }
        return RecordingValidationResult(status: .valid, durationSeconds: durationSeconds, overallRMS: overallRMS)
    }
}

public enum ListeningHUDRevealPlanner {
    public static let defaultDelaySeconds: TimeInterval = HUDRevealDelay.defaultDelay.seconds

    public static func shouldReveal(isRecording: Bool, cancelled: Bool) -> Bool {
        isRecording && !cancelled
    }
}

public enum RecordingStopFailurePresentationPlanner {
    public static func shouldShowHUD(
        validationStatus: RecordingValidationResult.Status?,
        listeningHUDWasShown: Bool
    ) -> Bool {
        !(validationStatus == .tooShort && !listeningHUDWasShown)
    }
}

public enum RecordingStopCancellationPlanner {
    public static func shouldCancelRecordingSource(recordingStopInProgress: Bool) -> Bool {
        !recordingStopInProgress
    }
}
