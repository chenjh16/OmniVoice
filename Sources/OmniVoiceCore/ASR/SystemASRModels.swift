import Foundation

public enum SystemASREngine: String, CaseIterable, Codable, Sendable {
    case speechAnalyzer = "speech_analyzer"
    case classicSpeech = "classic_speech"
    case appleOnlineSpeech = "apple_online_speech"

    public static let defaultEngine: SystemASREngine = .speechAnalyzer

    public func displayName(in uiLanguage: UILanguage) -> String {
        switch (uiLanguage, self) {
        case (.chinese, .speechAnalyzer): return "SpeechAnalyzer"
        case (.chinese, .classicSpeech): return "经典 Speech"
        case (.chinese, .appleOnlineSpeech): return "Apple 在线识别"
        case (.english, .speechAnalyzer): return "SpeechAnalyzer"
        case (.english, .classicSpeech): return "Classic Speech"
        case (.english, .appleOnlineSpeech): return "Apple Online Speech"
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
        case .classicSpeech, .appleOnlineSpeech:
            return [primary]
        }
    }
}

public struct SystemASRSettings: Equatable, Sendable {
    public let engine: SystemASREngine
    public let keywordHintsEnabled: Bool

    public init(
        engine: SystemASREngine = .defaultEngine,
        keywordHintsEnabled: Bool = true
    ) {
        self.engine = engine
        self.keywordHintsEnabled = keywordHintsEnabled
    }

    public static let defaultSettings = SystemASRSettings()
}
