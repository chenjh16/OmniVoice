import Foundation

/// UserDefaults-backed runtime flags.
///
/// App configuration is owned by `AppConfigStore`. Existing config-shaped
/// accessors remain for isolated tests and older stored defaults, but new
/// production code should read and write user-facing configuration through the
/// effective config object instead of this store.
public final class SettingsStore: @unchecked Sendable {
    public static let shared = SettingsStore()

    public enum Key {
        public static let selectedModel = "OmniVoice.selectedModel"
        public static let selectedTextLLMModel = "OmniVoice.selectedTextLLMModel"
        public static let pipelineMode = "OmniVoice.pipelineMode"
        public static let systemASREngine = "OmniVoice.systemASREngine"
        public static let systemASRKeywordHintsEnabled = "OmniVoice.systemASRKeywordHintsEnabled"
        public static let language = "OmniVoice.language"
        public static let uiLanguage = "OmniVoice.uiLanguage"
        public static let style = "OmniVoice.transcriptionStyle"
        public static let keywordHintsEnabled = "OmniVoice.keywordHintsEnabled"
        public static let enabledKeywordGroupIDs = "OmniVoice.enabledKeywordGroupIDs"
        public static let triggerKeyIdentifier = "OmniVoice.triggerKeyIdentifier"
        public static let continuousRecordingDoubleTapEnabled = "OmniVoice.continuousRecordingDoubleTapEnabled"
        public static let minRecordingDuration = "OmniVoice.minRecordingDuration"
        public static let maxRecordingDuration = "OmniVoice.maxRecordingDuration"
        public static let autoInsert = "OmniVoice.autoInsert"
        public static let listeningEnabled = "OmniVoice.listeningEnabled"
        public static let didRunStartupPermissionGuide = "OmniVoice.didRunStartupPermissionGuide"
        public static let startupPermissionGuideIdentity = "OmniVoice.startupPermissionGuideIdentity"
        public static let runtimeActive = "OmniVoice.runtimeActive"
        public static let stopReason = "OmniVoice.stopReason"
        public static let hudVisualStyle = "OmniVoice.hudVisualStyle"
        public static let hudMessageDuration = "OmniVoice.hudMessageDuration"
        public static let hudRevealDelay = "OmniVoice.hudRevealDelay"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Key.selectedModel: AllowedSpeechModel.defaultModel.rawValue,
            Key.selectedTextLLMModel: AllowedSpeechModel.defaultTextLLMModel.rawValue,
            Key.pipelineMode: TranscriptionPipelineMode.defaultMode.rawValue,
            Key.systemASREngine: SystemASREngine.defaultEngine.rawValue,
            Key.systemASRKeywordHintsEnabled: true,
            Key.language: LanguagePreference.defaultLanguage.rawValue,
            Key.uiLanguage: UILanguage.defaultLanguage.rawValue,
            Key.style: TranscriptionStyle.defaultStyle.rawValue,
            Key.keywordHintsEnabled: false,
            Key.enabledKeywordGroupIDs: ConfigPreferences.defaultEnabledKeywordGroupIDs,
            Key.triggerKeyIdentifier: TriggerKey.defaultTrigger.identifier,
            Key.continuousRecordingDoubleTapEnabled: false,
            Key.minRecordingDuration: MinRecordingDuration.defaultDuration.rawValue,
            Key.maxRecordingDuration: MaxRecordingDuration.defaultDuration.rawValue,
            Key.autoInsert: true,
            Key.listeningEnabled: true,
            Key.hudVisualStyle: HUDVisualStyle.defaultStyle.rawValue,
            Key.hudMessageDuration: HUDMessageDuration.defaultDuration.rawValue,
            Key.hudRevealDelay: HUDRevealDelay.defaultDelay.rawValue
        ])
    }

    public var selectedModel: AllowedSpeechModel {
        get { AllowedSpeechModel.safeSelection(defaults.string(forKey: Key.selectedModel)) }
        set { defaults.set(newValue.rawValue, forKey: Key.selectedModel) }
    }

    public var selectedTextLLMModel: AllowedSpeechModel {
        get {
            AllowedSpeechModel.safeSelection(
                defaults.string(forKey: Key.selectedTextLLMModel),
                fallback: .defaultTextLLMModel
            )
        }
        set { defaults.set(newValue.rawValue, forKey: Key.selectedTextLLMModel) }
    }

    public var pipelineMode: TranscriptionPipelineMode {
        get { TranscriptionPipelineMode(rawValue: defaults.string(forKey: Key.pipelineMode) ?? "") ?? .defaultMode }
        set { defaults.set(newValue.rawValue, forKey: Key.pipelineMode) }
    }

    public var systemASREngine: SystemASREngine {
        get { SystemASREngine(rawValue: defaults.string(forKey: Key.systemASREngine) ?? "") ?? .defaultEngine }
        set { defaults.set(newValue.rawValue, forKey: Key.systemASREngine) }
    }

    public var systemASRKeywordHintsEnabled: Bool {
        get { defaults.bool(forKey: Key.systemASRKeywordHintsEnabled) }
        set { defaults.set(newValue, forKey: Key.systemASRKeywordHintsEnabled) }
    }

    public var language: LanguagePreference {
        get {
            guard let raw = defaults.string(forKey: Key.language),
                  let language = LanguagePreference(rawValue: raw) else {
                return .defaultLanguage
            }
            return language
        }
        set { defaults.set(newValue.rawValue, forKey: Key.language) }
    }

    public var uiLanguage: UILanguage {
        get { UILanguage.safeSelection(defaults.string(forKey: Key.uiLanguage)) }
        set { defaults.set(newValue.rawValue, forKey: Key.uiLanguage) }
    }

    public var transcriptionStyle: TranscriptionStyle {
        get {
            guard let raw = defaults.string(forKey: Key.style),
                  let style = TranscriptionStyle(rawValue: raw) else {
                return .defaultStyle
            }
            return style
        }
        set { defaults.set(newValue.rawValue, forKey: Key.style) }
    }

    public var transcriptionStyleSelection: TranscriptionStyleSelection {
        get {
            TranscriptionStyleSelection(
                rawValue: defaults.string(forKey: Key.style) ?? TranscriptionStyleSelection.defaultSelection.rawValue
            )
        }
        set { defaults.set(newValue.rawValue, forKey: Key.style) }
    }

    public var keywordHintsEnabled: Bool {
        get { defaults.bool(forKey: Key.keywordHintsEnabled) }
        set { defaults.set(newValue, forKey: Key.keywordHintsEnabled) }
    }

    public var enabledKeywordGroupIDs: [String] {
        get { defaults.stringArray(forKey: Key.enabledKeywordGroupIDs) ?? [] }
        set { defaults.set(newValue, forKey: Key.enabledKeywordGroupIDs) }
    }

    public var triggerKey: TriggerKey {
        get { TriggerKey.candidate(identifier: defaults.string(forKey: Key.triggerKeyIdentifier)) }
        set { defaults.set(newValue.identifier, forKey: Key.triggerKeyIdentifier) }
    }

    public var continuousRecordingDoubleTapEnabled: Bool {
        get { defaults.bool(forKey: Key.continuousRecordingDoubleTapEnabled) }
        set { defaults.set(newValue, forKey: Key.continuousRecordingDoubleTapEnabled) }
    }

    public var maxRecordingDuration: MaxRecordingDuration {
        get { MaxRecordingDuration.safeSelection(defaults.integer(forKey: Key.maxRecordingDuration)) }
        set { defaults.set(newValue.rawValue, forKey: Key.maxRecordingDuration) }
    }

    public var minRecordingDuration: MinRecordingDuration {
        get { MinRecordingDuration.safeSelection(defaults.integer(forKey: Key.minRecordingDuration)) }
        set { defaults.set(newValue.rawValue, forKey: Key.minRecordingDuration) }
    }

    public var autoInsert: Bool {
        get { defaults.bool(forKey: Key.autoInsert) }
        set { defaults.set(newValue, forKey: Key.autoInsert) }
    }

    public var listeningEnabled: Bool {
        get { defaults.bool(forKey: Key.listeningEnabled) }
        set { defaults.set(newValue, forKey: Key.listeningEnabled) }
    }

    public var didRunStartupPermissionGuide: Bool {
        get { defaults.bool(forKey: Key.didRunStartupPermissionGuide) }
        set { defaults.set(newValue, forKey: Key.didRunStartupPermissionGuide) }
    }

    public var startupPermissionGuideIdentity: String? {
        get { defaults.string(forKey: Key.startupPermissionGuideIdentity) }
        set { defaults.set(newValue, forKey: Key.startupPermissionGuideIdentity) }
    }

    public var runtimeActive: Bool {
        get { defaults.bool(forKey: Key.runtimeActive) }
        set { defaults.set(newValue, forKey: Key.runtimeActive) }
    }

    public var stopReason: StopReason? {
        get {
            guard let raw = defaults.string(forKey: Key.stopReason) else {
                return nil
            }
            return StopReason(rawValue: raw)
        }
        set {
            if let newValue {
                defaults.set(newValue.rawValue, forKey: Key.stopReason)
            } else {
                defaults.removeObject(forKey: Key.stopReason)
            }
        }
    }

    public var hudVisualStyle: HUDVisualStyle {
        get { HUDVisualStyle.safeSelection(defaults.string(forKey: Key.hudVisualStyle)) }
        set { defaults.set(newValue.rawValue, forKey: Key.hudVisualStyle) }
    }

    public var hudMessageDuration: HUDMessageDuration {
        get { HUDMessageDuration.safeSelection(defaults.integer(forKey: Key.hudMessageDuration)) }
        set { defaults.set(newValue.rawValue, forKey: Key.hudMessageDuration) }
    }

    public var hudRevealDelay: HUDRevealDelay {
        get { HUDRevealDelay.safeSelection(defaults.integer(forKey: Key.hudRevealDelay)) }
        set { defaults.set(newValue.rawValue, forKey: Key.hudRevealDelay) }
    }

    public func applyConfigPreferences(_ preferences: ConfigPreferences) {
        selectedModel = preferences.selectedModel
        uiLanguage = preferences.uiLanguage
        transcriptionStyleSelection = preferences.transcriptionStyleSelection
        keywordHintsEnabled = preferences.keywordHintsEnabled
        enabledKeywordGroupIDs = preferences.enabledKeywordGroupIDs
        triggerKey = preferences.triggerKey
        continuousRecordingDoubleTapEnabled = preferences.continuousRecordingDoubleTapEnabled
        minRecordingDuration = preferences.minRecordingDuration
        maxRecordingDuration = preferences.maxRecordingDuration
        autoInsert = preferences.autoInsert
        hudVisualStyle = preferences.hudVisualStyle
        hudMessageDuration = preferences.hudMessageDuration
        hudRevealDelay = preferences.hudRevealDelay
    }

    public func configPreferences(launchAtLogin: Bool) -> ConfigPreferences {
        ConfigPreferences(
            selectedModel: selectedModel,
            uiLanguage: uiLanguage,
            transcriptionStyleSelection: transcriptionStyleSelection,
            keywordHintsEnabled: keywordHintsEnabled,
            enabledKeywordGroupIDs: enabledKeywordGroupIDs,
            triggerKey: triggerKey,
            continuousRecordingDoubleTapEnabled: continuousRecordingDoubleTapEnabled,
            minRecordingDuration: minRecordingDuration,
            maxRecordingDuration: maxRecordingDuration,
            autoInsert: autoInsert,
            launchAtLogin: launchAtLogin,
            hudVisualStyle: hudVisualStyle,
            hudMessageDuration: hudMessageDuration,
            hudRevealDelay: hudRevealDelay
        )
    }
}

public enum AppSafetyPlanner {
    public static func shouldStartInSafeMode(previousRuntimeActive: Bool) -> Bool {
        previousRuntimeActive
    }
}
