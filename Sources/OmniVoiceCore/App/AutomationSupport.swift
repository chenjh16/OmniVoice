import Foundation

public protocol ReplayRecordingSource: RecordingSource {
    func waitUntilReplayFinished() async
}

public struct RecordingReplayAutomationOptions: Sendable {
    public let model: AllowedSpeechModel?
    public let styleSelection: TranscriptionStyleSelection?
    public let expectedKeywords: [String]
    public let forceAutoInsert: Bool
    public let forceActionPanel: Bool
    public let targetBundleIdentifier: String?
    public let hudVisualStyle: HUDVisualStyle?
    public let uiLanguage: UILanguage?
    public let recordGUIFrames: Bool
    public let guiFrameIntervalSeconds: Double

    public init(
        model: AllowedSpeechModel? = nil,
        styleSelection: TranscriptionStyleSelection? = nil,
        expectedKeywords: [String] = [],
        forceAutoInsert: Bool = true,
        forceActionPanel: Bool = false,
        targetBundleIdentifier: String? = nil,
        hudVisualStyle: HUDVisualStyle? = nil,
        uiLanguage: UILanguage? = nil,
        recordGUIFrames: Bool = false,
        guiFrameIntervalSeconds: Double = 1.0 / 12.0
    ) {
        self.model = model
        self.styleSelection = styleSelection
        self.expectedKeywords = expectedKeywords
        self.forceAutoInsert = forceAutoInsert
        self.forceActionPanel = forceActionPanel
        self.targetBundleIdentifier = targetBundleIdentifier
        self.hudVisualStyle = hudVisualStyle
        self.uiLanguage = uiLanguage
        self.recordGUIFrames = recordGUIFrames
        self.guiFrameIntervalSeconds = guiFrameIntervalSeconds
    }
}

public struct TranscriptQualitySummary: Equatable, Sendable {
    public let finalTextCharacterCount: Int
    public let expectedKeywords: [String]
    public let matchedKeywords: [String]
    public let missingKeywords: [String]
    public let passed: Bool

    public var expectedCount: Int { expectedKeywords.count }
    public var matchedCount: Int { matchedKeywords.count }

    public static func evaluate(finalText: String, expectedKeywords: [String]) -> TranscriptQualitySummary? {
        let expected = expectedKeywords.compactMap { $0.nilIfBlank }
        guard !expected.isEmpty else { return nil }
        let normalizedText = finalText.lowercased()
        let matched = expected.filter { normalizedText.contains($0.lowercased()) }
        let missing = expected.filter { !matched.contains($0) }
        let requiredMatches = max(1, Int(ceil(Double(expected.count) * 0.8)))
        return TranscriptQualitySummary(
            finalTextCharacterCount: finalText.count,
            expectedKeywords: expected,
            matchedKeywords: matched,
            missingKeywords: missing,
            passed: matched.count >= requiredMatches
        )
    }
}

public struct RecordingReplayAutomationResult: Sendable {
    public let ok: Bool
    public let recordingSeconds: Double?
    public let wavBytes: Int?
    public let overallRMS: Float?
    public let originalBundleIdentifier: String?
    public let originalAppName: String?
    public let originalFocusFailure: String?
    public let injectionResult: String?
    public let fallbackReason: String?
    public let errorKind: String?
    public let qualitySummary: TranscriptQualitySummary?

    public init(
        ok: Bool,
        recordingSeconds: Double?,
        wavBytes: Int?,
        overallRMS: Float?,
        originalBundleIdentifier: String?,
        originalAppName: String?,
        originalFocusFailure: String?,
        injectionResult: String?,
        fallbackReason: String?,
        errorKind: String?,
        qualitySummary: TranscriptQualitySummary? = nil
    ) {
        self.ok = ok
        self.recordingSeconds = recordingSeconds
        self.wavBytes = wavBytes
        self.overallRMS = overallRMS
        self.originalBundleIdentifier = originalBundleIdentifier
        self.originalAppName = originalAppName
        self.originalFocusFailure = originalFocusFailure
        self.injectionResult = injectionResult
        self.fallbackReason = fallbackReason
        self.errorKind = errorKind
        self.qualitySummary = qualitySummary
    }
}

public struct AutomationEvent: Sendable {
    public let stage: String
    public let timestamp: Date
    public let errorKind: String?
    public let details: [String: String]
    public let surface: SurfaceDiagnosticSnapshot?
    public let screenshotPNGData: Data?

    public init(
        stage: String,
        timestamp: Date = Date(),
        errorKind: String? = nil,
        details: [String: String] = [:],
        surface: SurfaceDiagnosticSnapshot? = nil,
        screenshotPNGData: Data? = nil
    ) {
        self.stage = stage
        self.timestamp = timestamp
        self.errorKind = errorKind
        self.details = details
        self.surface = surface
        self.screenshotPNGData = screenshotPNGData
    }
}

@MainActor
public protocol AutomationEventSink: AnyObject {
    func record(_ event: AutomationEvent)
}

@MainActor
public enum OmniVoiceAutomationRunner {
    public static func runRecordingReplay(
        recordingSource: any RecordingSource,
        configLoader: ConfigLoader,
        eventSink: (any AutomationEventSink)?,
        options: RecordingReplayAutomationOptions
    ) async -> RecordingReplayAutomationResult {
        let coordinator = AppCoordinator(
            recordingSource: recordingSource,
            configStore: AppConfigStore(loader: configLoader),
            automationEventSink: eventSink
        )
        return await coordinator.runRecordingReplayForAutomation(options: options)
    }
}
