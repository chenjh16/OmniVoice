import Foundation

public enum SystemASREngine: String, CaseIterable, Codable, Sendable {
    case speechAnalyzer = "speech_analyzer"
    case classicSpeech = "classic_speech"
    case appleOnlineSpeech = "apple_online_speech"
    case externalASR = "external_asr"

    public static let defaultEngine: SystemASREngine = .speechAnalyzer
    public static let builtInMenuCases: [SystemASREngine] = [
        .speechAnalyzer,
        .classicSpeech,
        .appleOnlineSpeech
    ]

    public func displayName(in uiLanguage: UILanguage) -> String {
        switch (uiLanguage, self) {
        case (.chinese, .speechAnalyzer): return "SpeechAnalyzer"
        case (.chinese, .classicSpeech): return "经典 Speech"
        case (.chinese, .appleOnlineSpeech): return "Apple 在线识别"
        case (.chinese, .externalASR): return "外部 ASR"
        case (.english, .speechAnalyzer): return "SpeechAnalyzer"
        case (.english, .classicSpeech): return "Classic Speech"
        case (.english, .appleOnlineSpeech): return "Apple Online Speech"
        case (.english, .externalASR): return "External ASR"
        }
    }
}

public enum SystemASREngineAvailabilityResolver {
    public static func speechAnalyzerAvailable(osMajorVersion: Int) -> Bool {
        osMajorVersion >= 26
    }

    public static func effectiveEngine(
        configured: SystemASREngine,
        osMajorVersion: Int
    ) -> SystemASREngine {
        guard configured == .speechAnalyzer,
              !speechAnalyzerAvailable(osMajorVersion: osMajorVersion) else {
            return configured
        }
        return .classicSpeech
    }
}

public enum LiveASREngineFallbackPlanner {
    public static func engines(primary: SystemASREngine) -> [SystemASREngine] {
        switch primary {
        case .speechAnalyzer:
            return [.speechAnalyzer, .classicSpeech]
        case .classicSpeech, .appleOnlineSpeech, .externalASR:
            return [primary]
        }
    }
}

public enum SystemASRRuntimeRecoveryEvent: String, CaseIterable, Sendable {
    case willSleep = "will_sleep"
    case didWake = "did_wake"
    case screensDidSleep = "screens_did_sleep"
    case screensDidWake = "screens_did_wake"
    case screenLocked = "screen_locked"
    case screenUnlocked = "screen_unlocked"
    case speechAnalyzerStartFailed = "speech_analyzer_start_failed"
    case speechAnalyzerProbeFailed = "speech_analyzer_probe_failed"
}

public enum SystemASRRuntimeRecoveryPlanner {
    public static let wakeCooldownSeconds: TimeInterval = 45
    public static let failedStartCooldownSeconds: TimeInterval = 60
    public static let probeDelaySeconds: TimeInterval = 4

    public static func preferredLiveEngine(
        configured: SystemASREngine,
        now: Date,
        speechAnalyzerCooldownUntil: Date?
    ) -> SystemASREngine {
        guard configured == .speechAnalyzer,
              let cooldownUntil = speechAnalyzerCooldownUntil,
              now < cooldownUntil else {
            return configured
        }
        return .classicSpeech
    }

    public static func shouldScheduleSpeechAnalyzerProbe(
        configured: SystemASREngine,
        speechAnalyzerAvailable: Bool
    ) -> Bool {
        configured == .speechAnalyzer && speechAnalyzerAvailable
    }

    public static func cooldownUntil(
        event: SystemASRRuntimeRecoveryEvent,
        now: Date
    ) -> Date? {
        switch event {
        case .didWake, .screensDidWake, .screenUnlocked:
            return now.addingTimeInterval(wakeCooldownSeconds)
        case .speechAnalyzerStartFailed, .speechAnalyzerProbeFailed:
            return now.addingTimeInterval(failedStartCooldownSeconds)
        case .willSleep, .screensDidSleep, .screenLocked:
            return nil
        }
    }
}

public struct SystemASRSettings: Equatable, Sendable {
    public let engine: SystemASREngine
    public let keywordHintsEnabled: Bool
    public let externalASR: ExternalASRSettings

    public init(
        engine: SystemASREngine = .defaultEngine,
        keywordHintsEnabled: Bool = true,
        externalASR: ExternalASRSettings = .defaultSettings
    ) {
        self.engine = engine
        self.keywordHintsEnabled = keywordHintsEnabled
        self.externalASR = externalASR
    }

    public static let defaultSettings = SystemASRSettings()
}
