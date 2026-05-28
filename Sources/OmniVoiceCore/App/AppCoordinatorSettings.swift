import Foundation

@MainActor
final class AppCoordinatorSettings {
    let configStore: AppConfigStore
    let runtime: SettingsStore

    init(configStore: AppConfigStore, runtime: SettingsStore = .shared) {
        self.configStore = configStore
        self.runtime = runtime
    }

    var selectedModel: AllowedSpeechModel {
        get { configStore.config.modelCatalogs.inputAudioDefaultModel }
        set { configStore.updateModelSettingsInMemory(inputAudioModel: newValue) }
    }

    var selectedTextLLMModel: AllowedSpeechModel {
        get { configStore.config.modelCatalogs.textLLMDefaultModel }
        set { configStore.updateModelSettingsInMemory(textLLMModel: newValue) }
    }

    var pipelineMode: TranscriptionPipelineMode {
        get { configStore.config.pipelineMode }
        set { configStore.updateModelSettingsInMemory(pipelineMode: newValue) }
    }

    var systemASREngine: SystemASREngine {
        get { configStore.config.systemASRSettings.engine }
        set {
            configStore.updateModelSettingsInMemory(
                systemASRSettings: SystemASRSettings(
                    engine: newValue,
                    keywordHintsEnabled: systemASRKeywordHintsEnabled,
                    externalASR: configStore.config.systemASRSettings.externalASR
                )
            )
        }
    }

    var externalASRProviderID: String? {
        get { configStore.config.systemASRSettings.externalASR.providerID }
        set {
            configStore.updateModelSettingsInMemory(
                systemASRSettings: SystemASRSettings(
                    engine: systemASREngine,
                    keywordHintsEnabled: systemASRKeywordHintsEnabled,
                    externalASR: ExternalASRSettings(providerID: newValue)
                )
            )
        }
    }

    var systemASRKeywordHintsEnabled: Bool {
        get { configStore.config.systemASRSettings.keywordHintsEnabled }
        set {
            configStore.updateModelSettingsInMemory(
                systemASRSettings: SystemASRSettings(
                    engine: systemASREngine,
                    keywordHintsEnabled: newValue,
                    externalASR: configStore.config.systemASRSettings.externalASR
                )
            )
        }
    }

    var uiLanguage: UILanguage {
        get { configStore.config.preferences.uiLanguage }
        set { updatePreferences { $0.updating(uiLanguage: newValue) } }
    }

    var transcriptionStyleSelection: TranscriptionStyleSelection {
        get { configStore.config.preferences.transcriptionStyleSelection }
        set { updatePreferences { $0.updating(transcriptionStyleSelection: newValue) } }
    }

    var keywordHintsEnabled: Bool {
        get { configStore.config.preferences.keywordHintsEnabled }
        set { updatePreferences { $0.updating(keywordHintsEnabled: newValue) } }
    }

    var enabledKeywordGroupIDs: [String] {
        get { configStore.config.preferences.enabledKeywordGroupIDs }
        set { updatePreferences { $0.updating(enabledKeywordGroupIDs: newValue) } }
    }

    var triggerKey: TriggerKey {
        get { configStore.config.preferences.triggerKey }
        set { updatePreferences { $0.updating(triggerKey: newValue) } }
    }

    var continuousRecordingDoubleTapEnabled: Bool {
        get { configStore.config.preferences.continuousRecordingDoubleTapEnabled }
        set { updatePreferences { $0.updating(continuousRecordingDoubleTapEnabled: newValue) } }
    }

    var minRecordingDuration: MinRecordingDuration {
        get { configStore.config.preferences.minRecordingDuration }
        set { updatePreferences { $0.updating(minRecordingDuration: newValue) } }
    }

    var maxRecordingDuration: MaxRecordingDuration {
        get { configStore.config.preferences.maxRecordingDuration }
        set { updatePreferences { $0.updating(maxRecordingDuration: newValue) } }
    }

    var autoInsert: Bool {
        get { configStore.config.preferences.autoInsert }
        set { updatePreferences { $0.updating(autoInsert: newValue) } }
    }

    var hudVisualStyle: HUDVisualStyle {
        get { configStore.config.preferences.hudVisualStyle }
        set { updatePreferences { $0.updating(hudVisualStyle: newValue) } }
    }

    var hudMessageDuration: HUDMessageDuration {
        get { configStore.config.preferences.hudMessageDuration }
        set { updatePreferences { $0.updating(hudMessageDuration: newValue) } }
    }

    var hudRevealDelay: HUDRevealDelay {
        get { configStore.config.preferences.hudRevealDelay }
        set { updatePreferences { $0.updating(hudRevealDelay: newValue) } }
    }

    var liveASRPreviewEnabled: Bool {
        get { configStore.config.preferences.liveASRPreviewEnabled }
        set { updatePreferences { $0.updating(liveASRPreviewEnabled: newValue) } }
    }

    var listeningEnabled: Bool {
        get { runtime.listeningEnabled }
        set { runtime.listeningEnabled = newValue }
    }

    var didRunStartupPermissionGuide: Bool {
        get { runtime.didRunStartupPermissionGuide }
        set { runtime.didRunStartupPermissionGuide = newValue }
    }

    var startupPermissionGuideIdentity: String? {
        get { runtime.startupPermissionGuideIdentity }
        set { runtime.startupPermissionGuideIdentity = newValue }
    }

    var runtimeActive: Bool {
        get { runtime.runtimeActive }
        set { runtime.runtimeActive = newValue }
    }

    var stopReason: StopReason? {
        get { runtime.stopReason }
        set { runtime.stopReason = newValue }
    }

    func applyConfigPreferences(_ preferences: ConfigPreferences) {
        configStore.updatePreferencesInMemory { _ in preferences }
    }

    func configPreferences(launchAtLogin: Bool) -> ConfigPreferences {
        configStore.config.preferences.updating(
            selectedModel: selectedModel,
            launchAtLogin: launchAtLogin
        )
    }

    func updatePreferences(_ transform: (ConfigPreferences) -> ConfigPreferences) {
        configStore.updatePreferencesInMemory(transform)
    }
}
