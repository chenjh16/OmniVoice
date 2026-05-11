import AppKit
import Foundation

public enum MenuLayoutMetrics {
    public static let customViewLeading: CGFloat = 28
}

struct AccessibilityPermissionRequestOutcome: Sendable {
    let snapshot: PermissionSnapshot
    let openedSettingsFallback: Bool
}

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
                    keywordHintsEnabled: systemASRKeywordHintsEnabled
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
                    keywordHintsEnabled: newValue
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

enum TranscriptionFlowControl: Error {
    case asrDraftShown
}

@MainActor
final class AppCoordinator: NSObject, NSMenuDelegate {
    enum AppState {
        case idle
        case recording
        case transcribing
    }

    let configStore: AppConfigStore
    let settings: AppCoordinatorSettings
    var client: any TranscriptionClient
    let recordingSource: any RecordingSource
    weak var automationEventSink: (any AutomationEventSink)?
    let eventTap = EventTapController()
    let hud = DictationHUDController()
    let actionPanel = ActionPanelController()
    let textInjector = TextInjector()
    let systemSpeechRecognizer = SystemSpeechRecognizer()
    let liveASRCoordinator = LiveASRCoordinator()
    let recordingPipeline = RecordingPipelineCoordinator()
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let configWatcher: ConfigFileWatcher

    var state: AppState = .idle
    var maxRecordingTimer: Timer?
    var listeningHUDRevealTimer: Timer?
    var listeningHUDShownForCurrentRecording = false
    var transcriptionTask: Task<Void, Never>?
    var recordingFocus: FocusSnapshot?
    var recordingStartDate: Date?
    var continuousRecordingStateMachine = ContinuousRecordingStateMachine()
    var continuousRecordingTapTimeout: DispatchWorkItem?
    var continuousRecordingStopFallback: DispatchWorkItem?
    var tapStatus: String?
    var isTestingConnection = false
    var lastTestConnectionResult: TestConnectionResult?
    var lastDiagnostic: RuntimeDiagnostic?
    var globalStopActive = false
    var stopReason: StopReason?
    var lastPermissionSnapshot: PermissionSnapshot?
    var permissionReadinessTimer: Timer?
    var permissionDriftTimer: Timer?
    var eventTapFailureHUDEnabled = false
    var pendingTranscription: PendingTranscription?
    var lastLaunchAtLoginError: String?
    let triggerCapture = TriggerCaptureController()
    var triggerCaptureTimeout: Timer?
    weak var triggerCaptureView: TriggerCaptureMenuView?
    var triggerCapturePausedListening = false
    var systemASRRuntimeRecoveryObservers: [NSObjectProtocol] = []
    var speechAnalyzerRecoveryCooldownUntil: Date?
    var speechAnalyzerRecoveryProbeTask: Task<Void, Never>?
    var speechAnalyzerRecoveryGeneration = 0
    var sourceLatencyResults: [String: SourceLatencyMeasurement] = [:]
    var latencyTimer: Timer?
    var automationOptions: RecordingReplayAutomationOptions?
    var automationContinuation: CheckedContinuation<RecordingReplayAutomationResult, Never>?
    var automationRecordingResult: AudioRecordingResult?
    var automationGUIFrameTimer: Timer?
    var automationGUIFrameIndex = 0
    var automationPreviousUILanguage: UILanguage?
    var configHotReload = ConfigHotReloadController()

    var strings: UIStrings {
        UIStrings(language: settings.uiLanguage)
    }

    var currentStyleDescriptor: TranscriptionStyleDescriptor {
        TranscriptionStyleResolver.resolve(
            selection: settings.transcriptionStyleSelection,
            customStyles: config.customStyles
        )
    }

    var currentKeywordHintsContext: KeywordHintsContext {
        let enabledIDs = Set(settings.enabledKeywordGroupIDs)
        let groups = config.keywordGroups.filter { enabledIDs.contains($0.id) }
        return KeywordHintsContext(isEnabled: settings.keywordHintsEnabled, groups: groups)
    }

    var currentSystemASRKeywordHintsContext: KeywordHintsContext {
        let base = currentKeywordHintsContext
        return KeywordHintsContext(
            isEnabled: base.isEnabled && settings.systemASRKeywordHintsEnabled,
            groups: base.groups
        )
    }

    var selectedKeywordGroupCount: Int {
        currentKeywordHintsContext.activeGroups.count
    }

    var modelAvailabilityIndex: ModelAvailabilityIndex {
        let configuredSourceIDs = Set(config.sources.map(\.id))
        let measurements = sourceLatencyResults.filter { configuredSourceIDs.contains($0.key) }
        return ModelAvailabilityIndex(measurements: measurements, catalogs: config.modelCatalogs)
    }

    var currentPipelineModel: AllowedSpeechModel {
        switch settings.pipelineMode {
        case .inputAudio, .systemASROnly:
            return settings.selectedModel
        case .systemASRTextLLM:
            return settings.selectedTextLLMModel
        }
    }

    var continuousRecordingDoubleTapSupported: Bool {
        ContinuousRecordingTriggerSupportResolver.supportsDoubleTap(settings.triggerKey)
    }

    var shouldUseContinuousRecordingDoubleTap: Bool {
        settings.continuousRecordingDoubleTapEnabled && continuousRecordingDoubleTapSupported
    }

    var continuousRecordingDoubleTapInterval: TimeInterval {
        ContinuousRecordingTapPlanner.doubleTapInterval(systemInterval: NSEvent.doubleClickInterval)
    }

    var shouldRunLiveASRForCurrentRecording: Bool {
        true
    }

    var speechAnalyzerAvailable: Bool {
        SystemASREngineAvailabilityResolver.speechAnalyzerAvailable(
            osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        )
    }

    var effectiveSystemASREngine: SystemASREngine {
        SystemASREngineAvailabilityResolver.effectiveEngine(
            configured: settings.systemASREngine,
            osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        )
    }

    var effectiveLiveASREngine: SystemASREngine {
        SystemASRRuntimeRecoveryPlanner.preferredLiveEngine(
            configured: effectiveSystemASREngine,
            now: Date(),
            speechAnalyzerCooldownUntil: speechAnalyzerRecoveryCooldownUntil
        )
    }

    var warningDuration: TimeInterval {
        settings.hudMessageDuration.seconds
    }

    var permissionGuidanceDuration: TimeInterval {
        max(warningDuration, 10)
    }

    var accessibilityPromptFallbackDelay: UInt64 {
        6_000_000_000
    }

    var permissionRequestSettleDelay: UInt64 {
        700_000_000
    }

    var config: MimoConfig {
        configStore.config
    }

    init(
        recordingSource: any RecordingSource = AudioRecorder(),
        configStore: AppConfigStore? = nil,
        automationEventSink: (any AutomationEventSink)? = nil
    ) {
        let resolvedConfigStore = configStore ?? AppConfigStore.shared
        let loaded = resolvedConfigStore.ensureValidConfig(uiLanguage: resolvedConfigStore.config.preferences.uiLanguage)
        self.configStore = resolvedConfigStore
        self.settings = AppCoordinatorSettings(configStore: resolvedConfigStore)
        client = MimoAPIClient(config: loaded.resolvingSource(using: [:]))
        self.recordingSource = recordingSource
        self.configWatcher = ConfigFileWatcher(fileURL: resolvedConfigStore.configFileURL)
        self.automationEventSink = automationEventSink
        super.init()
        settings.applyConfigPreferences(loaded.preferences)
        applyConfigModelSettings(loaded)
        client = makeClient(config: loaded)
        self.recordingSource.onRMSLevel = { [weak self] level in
            DispatchQueue.main.async {
                self?.hud.updateRMSLevel(level)
            }
        }
        self.recordingSource.onSampleChunk = { [weak self] chunk in
            DispatchQueue.main.async {
                self?.handleLiveASRChunk(chunk)
            }
        }
        eventTap.onSignal = { [weak self] signal in
            DispatchQueue.main.async {
                self?.handleEventTapSignal(signal)
            }
        }
        triggerCapture.onSignal = { [weak self] signal in
            DispatchQueue.main.async {
                self?.handleTriggerCaptureSignal(signal)
            }
        }
        textInjector.onDiagnostic = { [weak self] diagnostic in
            self?.recordDiagnostic(diagnostic)
        }
        configWatcher.onChange = { [weak self] in
            DispatchQueue.main.async {
                self?.handleConfigFileChanged()
            }
        }
    }

    func applyConfigModelSettings(_ loaded: MimoConfig) {
        settings.selectedModel = loaded.modelCatalogs.inputAudioDefaultModel
        settings.selectedTextLLMModel = loaded.modelCatalogs.textLLMDefaultModel
        settings.pipelineMode = loaded.pipelineMode
        settings.systemASREngine = loaded.systemASRSettings.engine
        settings.systemASRKeywordHintsEnabled = loaded.systemASRSettings.keywordHintsEnabled
    }

    func makeClient(config: MimoConfig) -> any TranscriptionClient {
        MimoAPIClient(config: config.resolvingSource(using: sourceLatencyResults)) { [weak self] diagnostic in
            DispatchQueue.main.async {
                self?.recordDiagnostic(diagnostic)
            }
        }
    }

    func loadConfig() -> MimoConfig {
        configStore.ensureValidConfig(uiLanguage: settings.uiLanguage)
    }

    func applyLoadedConfigPreferences(_ loaded: MimoConfig, syncLaunchAtLogin: Bool) {
        settings.applyConfigPreferences(loaded.preferences)
        applyConfigModelSettings(loaded)
        normalizeHUDStyleAvailability()
        hud.setVisualStyle(settings.hudVisualStyle)
        actionPanel.setVisualStyle(settings.hudVisualStyle)
        eventTap.update(triggerKey: settings.triggerKey)
        eventTap.updateWatchdogTimeout(seconds: TimeInterval(settings.maxRecordingDuration.rawValue + 5))
        if syncLaunchAtLogin {
            syncLaunchAtLoginPreference(loaded.preferences.launchAtLogin, showWarningHUD: false)
        }
        if settings.listeningEnabled, !globalStopActive {
            tapStatus = eventTap.isRunning ? strings.listeningWithTrigger(settings.triggerKey) : tapStatus
        }
    }

    @discardableResult
    func persistCurrentPreferences() -> Bool {
        let preferences = settings.configPreferences(
            launchAtLogin: LaunchAtLoginController.status() == .enabled
        )
        markInternalConfigWrite()
        guard configStore.savePreferences(preferences) else {
            hud.showWarningStatus(strings.operationFailed, duration: warningDuration)
            return false
        }
        _ = configStore.saveModelAndPipelineSettings(
            inputAudioModel: settings.selectedModel,
            textLLMModel: settings.selectedTextLLMModel,
            pipelineMode: settings.pipelineMode,
            systemASRSettings: SystemASRSettings(
                engine: settings.systemASREngine,
                keywordHintsEnabled: settings.systemASRKeywordHintsEnabled
            ),
            uiLanguage: settings.uiLanguage
        )
        client = makeClient(config: config)
        return true
    }

    func syncLaunchAtLoginPreference(_ enabled: Bool, showWarningHUD: Bool) {
        let isEnabled = LaunchAtLoginController.status() == .enabled
        guard isEnabled != enabled else {
            lastLaunchAtLoginError = nil
            return
        }
        do {
            try LaunchAtLoginController.setEnabled(enabled)
            lastLaunchAtLoginError = nil
        } catch {
            lastLaunchAtLoginError = sanitizedMessage(for: error)
            if showWarningHUD {
                hud.showWarningStatus(lastLaunchAtLoginError ?? strings.operationFailed, duration: warningDuration)
            }
        }
    }

    func diagnosticRuntimeDetails(_ details: [String: String] = [:]) -> [String: String] {
        var output = details
        output["pid"] = "\(ProcessInfo.processInfo.processIdentifier)"
        output["install_identity"] = PermissionInstallIdentity.current()
        return output
    }

    func permissionDetails(_ snapshot: PermissionSnapshot) -> [String: String] {
        [
            "microphone": snapshot.microphoneGranted ? "granted" : "missing",
            "accessibility": snapshot.accessibilityGranted ? "granted" : "missing",
            "input_monitoring": snapshot.inputMonitoringGranted ? "granted" : "missing",
            "speech_recognition": snapshot.speechRecognitionGranted ? "granted" : "missing"
        ]
    }

    func otherRunningOmniVoiceApplications() -> [NSRunningApplication] {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: AppConstants.bundleIdentifier)
            .filter { $0.processIdentifier != currentPID && !$0.isTerminated }
    }

    @discardableResult
    func resolveOtherInstancesBeforeListening() -> SingleInstanceResolution {
        let apps = otherRunningOmniVoiceApplications()
        guard !apps.isEmpty else {
            return SingleInstanceResolution(observedCount: 0, remainingCount: 0)
        }
        apps.forEach { app in
            if !app.terminate() {
                app.forceTerminate()
            }
        }
        var remainingApps = waitForOtherInstancesToExit(timeout: 1.2)
        if !remainingApps.isEmpty {
            remainingApps.forEach { $0.forceTerminate() }
            remainingApps = waitForOtherInstancesToExit(timeout: 0.4)
        }
        return SingleInstanceResolution(
            observedCount: apps.count,
            remainingCount: remainingApps.count
        )
    }

    func waitForOtherInstancesToExit(timeout: TimeInterval) -> [NSRunningApplication] {
        let deadline = Date().addingTimeInterval(timeout)
        var remainingApps = otherRunningOmniVoiceApplications()
        while !remainingApps.isEmpty, Date() < deadline {
            let nextCheck = Date().addingTimeInterval(0.05)
            RunLoop.current.run(mode: .default, before: min(nextCheck, deadline))
            remainingApps = otherRunningOmniVoiceApplications()
        }
        return remainingApps
    }

    func updateEventTapTriggerSuppression() {
        eventTap.setTriggerSuppressionEnabled(
            settings.listeningEnabled &&
            !globalStopActive &&
            (state == .idle || state == .recording)
        )
    }

    func start() {
        normalizeHUDStyleAvailability()
        syncLaunchAtLoginPreference(config.preferences.launchAtLogin, showWarningHUD: false)
        let startupPermissionSnapshot = PermissionChecker.snapshot()
        lastPermissionSnapshot = startupPermissionSnapshot
        let singleInstanceResolution = resolveOtherInstancesBeforeListening()
        let hasOtherInstanceConflict = !SingleInstanceLaunchPlanner.shouldAllowListening(
            resolution: singleInstanceResolution
        )
        stopReason = settings.stopReason
        let migratedStopReason = PermissionLegacyStopReasonMigrationPlanner.inferredStopReason(
            listeningEnabled: settings.listeningEnabled,
            storedStopReason: stopReason,
            didRunStartupPermissionGuide: settings.didRunStartupPermissionGuide
        )
        if migratedStopReason != stopReason {
            stopReason = migratedStopReason
            settings.stopReason = migratedStopReason
            recordLocalDiagnostic(stage: "legacy_permission_blocked_stop_reason_migrated")
        }
        let shouldStartStopped = AppSafetyPlanner.shouldStartInSafeMode(
            previousRuntimeActive: settings.runtimeActive
        )
        settings.runtimeActive = true
        if hasOtherInstanceConflict {
            globalStopActive = true
            stopReason = .manual
            settings.stopReason = .manual
            settings.listeningEnabled = false
            tapStatus = strings.stopped
            recordLocalDiagnostic(
                stage: "other_instance_detected",
                errorKind: "single_instance_conflict",
                details: diagnosticRuntimeDetails([
                    "other_instances_observed": "\(singleInstanceResolution.observedCount)",
                    "other_instances_remaining": "\(singleInstanceResolution.remainingCount)",
                    "listening_enabled": "false"
                ])
            )
        } else if singleInstanceResolution.observedCount > 0 {
            recordLocalDiagnostic(
                stage: "other_instance_terminated",
                details: diagnosticRuntimeDetails([
                    "other_instances_observed": "\(singleInstanceResolution.observedCount)",
                    "other_instances_remaining": "\(singleInstanceResolution.remainingCount)"
                ])
            )
        } else if shouldStartStopped {
            globalStopActive = true
            stopReason = .previousRunRecovery
            settings.stopReason = .previousRunRecovery
            settings.listeningEnabled = false
            tapStatus = strings.stoppedAfterPreviousRun
        } else if PermissionStartupAutoEnablePlanner.shouldAutoEnable(
            listeningEnabled: settings.listeningEnabled,
            stopReason: stopReason,
            current: startupPermissionSnapshot
        ) {
            globalStopActive = false
            stopReason = nil
            settings.stopReason = nil
            settings.listeningEnabled = true
            tapStatus = strings.listeningWithTrigger(settings.triggerKey)
            recordLocalDiagnostic(stage: "permissions_ready_startup_auto_reenabled")
        } else if !settings.listeningEnabled {
            applyPersistedStoppedState()
        } else if settings.listeningEnabled, !startupPermissionSnapshot.allRequiredGranted {
            enterPermissionBlockedStop(recordDiagnostic: false)
        }
        configureStatusItem()
        startSystemASRRuntimeRecoveryMonitoring()
        configWatcher.start()
        hud.setVisualStyle(settings.hudVisualStyle)
        actionPanel.setVisualStyle(settings.hudVisualStyle)
        if hasOtherInstanceConflict {
            rebuildMenu()
        } else if shouldStartStopped {
            recordLocalDiagnostic(
                stage: "global_stop_enabled",
                errorKind: "previous_runtime_active",
                details: diagnosticRuntimeDetails(["auto_insert_paused": "true", "listening_enabled": "false"])
            )
        } else {
            rebuildMenu()
        }
        if settings.listeningEnabled {
            startListening(showFailureHUD: false)
        }
        scheduleLatencyChecks()
        Task { await runStartupPermissionGuideIfNeeded() }
        Task { await refreshModels(showStatus: false) }
    }

    func stop() {
        maxRecordingTimer?.invalidate()
        resetListeningHUDRevealState()
        latencyTimer?.invalidate()
        latencyTimer = nil
        configWatcher.stop()
        stopSystemASRRuntimeRecoveryMonitoring()
        stopPermissionReadinessPolling()
        stopPermissionDriftMonitoring()
        let stopWasPending = cancelPendingRecordingStop()
        transcriptionTask?.cancel()
        pendingTranscription?.liveASRFinalTask?.cancel()
        if RecordingStopCancellationPlanner.shouldCancelRecordingSource(recordingStopInProgress: stopWasPending) {
            recordingSource.cancel()
        }
        cancelLiveASRSession()
        hud.hide()
        actionPanel.cancel()
        recordingStartDate = nil
        eventTap.setCancellationActive(false)
        eventTap.setTriggerSuppressionEnabled(false)
        eventTap.stop()
        cancelTriggerCapture(restartListening: false)
        settings.runtimeActive = false
        statusItem.menu = nil
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func configureStatusItem() {
        statusItem.length = 23
        if let button = statusItem.button {
            button.image = makeStatusBarImage()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyUpOrDown
            button.toolTip = AppConstants.productName
        }
        statusItem.menu = NSMenu(title: AppConstants.productName)
        statusItem.menu?.delegate = self
    }

    func makeStatusBarImage() -> NSImage {
        let size = NSSize(width: 17, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()

        let barWidth: CGFloat = 1.85
        let spacing: CGFloat = 0.85
        let heights: [CGFloat] = [7.0, 12.0, 8.2, 4.9, 8.6, 5.9]
        let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * spacing
        var x = (size.width - totalWidth) / 2

        for height in heights {
            let rect = NSRect(
                x: x,
                y: (size.height - height) / 2,
                width: barWidth,
                height: height
            )
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            x += barWidth + spacing
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
