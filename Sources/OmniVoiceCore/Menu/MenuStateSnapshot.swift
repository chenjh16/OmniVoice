import Foundation

@MainActor
struct MenuStateSnapshot {
    let permissionSnapshot: PermissionSnapshot
    let displayConfig: MimoConfig
    let globalStopActive: Bool
    let listeningEnabled: Bool
    let statusTitle: String
    let pipelineMode: TranscriptionPipelineMode
    let currentPipelineModel: AllowedSpeechModel
    let systemASREngine: SystemASREngine
    let configWarnings: [String]
    let lastConfigHotReloadMessage: String?
    let uiLanguage: UILanguage
    let styleDescriptor: TranscriptionStyleDescriptor
    let keywordHintsEnabled: Bool
    let selectedKeywordGroupCount: Int
    let triggerKey: TriggerKey
    let minRecordingDuration: MinRecordingDuration
    let maxRecordingDuration: MaxRecordingDuration
    let launchAtLoginEnabled: Bool
    let autoInsert: Bool
    let lastLaunchAtLoginError: String?

    init(coordinator: AppCoordinator) {
        let settings = coordinator.settings
        permissionSnapshot = PermissionChecker.snapshot()
        displayConfig = coordinator.config.resolvingSource(using: coordinator.sourceLatencyResults)
        globalStopActive = coordinator.globalStopActive
        listeningEnabled = settings.listeningEnabled
        statusTitle = coordinator.statusTitle
        pipelineMode = settings.pipelineMode
        currentPipelineModel = coordinator.currentPipelineModel
        systemASREngine = coordinator.effectiveSystemASREngine
        configWarnings = coordinator.config.warnings
        lastConfigHotReloadMessage = coordinator.configHotReload.lastMessage
        uiLanguage = settings.uiLanguage
        styleDescriptor = coordinator.currentStyleDescriptor
        keywordHintsEnabled = settings.keywordHintsEnabled
        selectedKeywordGroupCount = coordinator.selectedKeywordGroupCount
        triggerKey = settings.triggerKey
        minRecordingDuration = settings.minRecordingDuration
        maxRecordingDuration = settings.maxRecordingDuration
        launchAtLoginEnabled = LaunchAtLoginController.status() == .enabled
        autoInsert = settings.autoInsert
        lastLaunchAtLoginError = coordinator.lastLaunchAtLoginError
    }
}
