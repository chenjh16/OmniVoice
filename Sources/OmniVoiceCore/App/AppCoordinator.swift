import AppKit
import Foundation

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
    let externalASRPluginRegistry: ExternalASRPluginRegistry
    var externalASRPlugins: [ExternalASRPlugin]
    let eventTap = EventTapController()
    let hud = DictationHUDController()
    let actionPanel = ActionPanelController()
    let textInjector = TextInjector()
    let systemSpeechRecognizer = SystemSpeechRecognizer()
    let liveASRCoordinator = LiveASRCoordinator()
    let recordingPipeline = RecordingPipelineCoordinator()
    lazy var menuActionRouter = MenuActionRouter(coordinator: self)
    lazy var permissionCoordinator = PermissionCoordinator(coordinator: self)
    lazy var listeningLifecycleCoordinator = ListeningLifecycleCoordinator(coordinator: self)
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let configWatcher: ConfigFileWatcher

    var state: AppState = .idle
    var transcriptionTask: Task<Void, Never>?
    let recordingSession = RecordingSessionRuntimeState()
    let recordingTimingRuntime = RecordingTimingRuntimeState()
    let sourceLatencyRuntime = SourceLatencyRuntimeState()
    let automationRuntime = RecordingReplayAutomationRuntimeState()
    let continuousRecordingRuntime = ContinuousRecordingRuntimeState()
    let permissionPollingRuntime = PermissionPollingRuntimeState()
    let triggerCaptureRuntime = TriggerCaptureRuntimeState()
    var tapStatus: String?
    var isTestingConnection = false
    var lastTestConnectionResult: TestConnectionResult?
    var lastDiagnostic: RuntimeDiagnostic?
    var globalStopActive = false
    var stopReason: StopReason?
    var lastPermissionSnapshot: PermissionSnapshot?
    var eventTapFailureHUDEnabled = false
    var lastLaunchAtLoginError: String?
    let triggerCapture = TriggerCaptureController()
    var systemASRRuntimeRecoveryObservers: [NSObjectProtocol] = []
    var speechAnalyzerRecoveryCooldownUntil: Date?
    var speechAnalyzerRecoveryProbeTask: Task<Void, Never>?
    var speechAnalyzerRecoveryGeneration = 0
    var configHotReload = ConfigHotReloadController()

    var recordingFocus: FocusSnapshot? {
        get { recordingSession.focus }
        set { recordingSession.focus = newValue }
    }

    var recordingStartDate: Date? {
        get { recordingSession.startDate }
        set { recordingSession.startDate = newValue }
    }

    var pendingTranscription: PendingTranscription? {
        get { recordingSession.pendingTranscription }
        set { recordingSession.pendingTranscription = newValue }
    }

    var automationOptions: RecordingReplayAutomationOptions? {
        get { automationRuntime.options }
        set { automationRuntime.options = newValue }
    }

    var automationContinuation: CheckedContinuation<RecordingReplayAutomationResult, Never>? {
        get { automationRuntime.continuation }
        set { automationRuntime.continuation = newValue }
    }

    var automationRecordingResult: AudioRecordingResult? {
        get { automationRuntime.recordingResult }
        set { automationRuntime.recordingResult = newValue }
    }

    var automationPreviousUILanguage: UILanguage? {
        get { automationRuntime.previousUILanguage }
        set { automationRuntime.previousUILanguage = newValue }
    }

    var listeningHUDShownForCurrentRecording: Bool {
        get { recordingTimingRuntime.listeningHUDShownForCurrentRecording }
        set { recordingTimingRuntime.listeningHUDShownForCurrentRecording = newValue }
    }

    var continuousRecordingTapTimeout: DispatchWorkItem? {
        get { continuousRecordingRuntime.tapTimeout.workItem }
        set { continuousRecordingRuntime.tapTimeout.replace(newValue) }
    }

    var continuousRecordingStopFallback: DispatchWorkItem? {
        get { continuousRecordingRuntime.stopFallback.workItem }
        set { continuousRecordingRuntime.stopFallback.replace(newValue) }
    }

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
        let measurements = sourceLatencyRuntime.results.filter { configuredSourceIDs.contains($0.key) }
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

    var selectedExternalASRPlugin: ExternalASRPlugin? {
        guard let providerID = settings.externalASRProviderID else { return nil }
        return externalASRPlugins.first { $0.id == providerID }
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
        automationEventSink: (any AutomationEventSink)? = nil,
        externalASRPluginRegistry: ExternalASRPluginRegistry = ExternalASRPluginRegistry()
    ) {
        let resolvedConfigStore = configStore ?? AppConfigStore.shared
        let loaded = resolvedConfigStore.ensureValidConfig(uiLanguage: resolvedConfigStore.config.preferences.uiLanguage)
        self.configStore = resolvedConfigStore
        self.settings = AppCoordinatorSettings(configStore: resolvedConfigStore)
        self.client = MimoAPIClient(config: loaded.resolvingSource(using: [:]))
        self.recordingSource = recordingSource
        self.externalASRPluginRegistry = externalASRPluginRegistry
        self.externalASRPlugins = externalASRPluginRegistry.discoverPlugins()
        self.configWatcher = ConfigFileWatcher(fileURL: resolvedConfigStore.configFileURL)
        self.automationEventSink = automationEventSink
        super.init()
        settings.applyConfigPreferences(loaded.preferences)
        applyConfigModelSettings(loaded)
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
        settings.externalASRProviderID = loaded.systemASRSettings.externalASR.providerID
        settings.systemASRKeywordHintsEnabled = loaded.systemASRSettings.keywordHintsEnabled
    }

    func reloadExternalASRPlugins() {
        externalASRPlugins = externalASRPluginRegistry.discoverPlugins()
    }

    func makeClient(config: MimoConfig) -> any TranscriptionClient {
        MimoAPIClient(config: config.resolvingSource(using: sourceLatencyRuntime.results)) { [weak self] diagnostic in
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
                keywordHintsEnabled: settings.systemASRKeywordHintsEnabled,
                externalASR: ExternalASRSettings(providerID: settings.externalASRProviderID)
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
        recordingTimingRuntime.maxRecordingTimer.cancel()
        resetListeningHUDRevealState()
        sourceLatencyRuntime.invalidateTimer()
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
