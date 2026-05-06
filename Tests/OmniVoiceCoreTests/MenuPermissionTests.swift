import Foundation
import ApplicationServices
import Testing
@testable import OmniVoiceCore
@testable import OmniVoiceE2ESupport

@Suite("Menu and permissions")
struct MenuPermissionTests {
    @Test
    func menuTitlesShowCurrentSelections() {
        #expect(MenuTitleFormatter.model(.mimoV2Omni) == "Model: mimo-v2-omni")
        #expect(MenuTitleFormatter.language(.chinese) == "Language: 中文")
        #expect(MenuTitleFormatter.style(.codeFaithful) == "Style: Technical")
        #expect(MenuTitleFormatter.recordingDuration(min: .milliseconds500, max: .seconds120) == "Duration: 500ms–120s")
        #expect(MenuTitleFormatter.language(.chinese, uiLanguage: .chinese) == "语言：中文")
        #expect(MenuTitleFormatter.style(.concise, uiLanguage: .chinese) == "风格：精炼")
        #expect(MenuTitleFormatter.style(.rewrite, uiLanguage: .chinese) == "风格：重写")
        #expect(MenuTitleFormatter.trigger(.leftControl, uiLanguage: .chinese) == "触发键：左 Control")
        #expect(TranscriptionStyle.menuOrder == [.verbatim, .concise, .codeFaithful, .rewrite])
        #expect(TranscriptionStyleSelection(rawValue: "codeFaithful").builtInStyle == .codeFaithful)
        let custom = CustomTranscriptionStyle(
            id: "meeting_notes",
            displayName: "Meeting Notes",
            displayNameZH: "会议纪要",
            description: "Notes",
            descriptionZH: "纪要",
            prompt: "整理成会议纪要"
        )
        let customDescriptor = TranscriptionStyleResolver.resolve(
            selection: .custom("meeting_notes"),
            customStyles: [custom]
        )
        #expect(MenuTitleFormatter.style(customDescriptor, uiLanguage: .chinese) == "风格：会议纪要（自定义）")
        #expect(UIStrings(language: .english).panelStyleSwitchTitle(customDescriptor) == "Style: Meeting Notes")
        #expect(UIStrings(language: .chinese).apiSourceTitle(MimoConfig(activeSourceID: "sgp")).contains("sgp"))
        #expect(UIStrings(language: .english).latencyIntervalTitle(.minutes30) == "Latency Check: Every 30 minutes")
        #expect(UIStrings(language: .chinese).latencyIntervalLabel(.seconds30) == "每 30 秒")
        #expect(ConfigLatencyInterval.allCases.map(\.rawValue) == [30, 60, 120, 300, 900, 1800, 3600, 0, -1])
        #expect(UIStrings(language: .chinese).configurationTitle(MimoConfig(apiKey: nil, source: .missing)).contains("缺少 API Key"))
        #expect(UIStrings(language: .chinese).apiKeyStatus(MimoConfig(apiKey: nil)) == "缺失")
        #expect(UIStrings(language: .chinese).configWarning("Config warning: config.jsonc could not be read").contains("无法读取"))
        #expect(UIStrings(language: .chinese).permissionManagement == "权限管理")
        #expect(UIStrings(language: .chinese).stop == "停止")
        #expect(UIStrings(language: .chinese).reenable == "重新启用")
        #expect(UIStrings(language: .chinese).openConfigFile == "打开 config 文件")
        #expect(UIStrings(language: .english).openConfigFile == "Open config file")
        #expect(UIStrings(language: .chinese).restart == "重启 OmniVoice")
        #expect(UIStrings(language: .english).quit == "Quit OmniVoice")
        #expect(UIStrings(language: .chinese).recordingDurationTitle(min: .milliseconds800, max: .seconds60) == "录音时长：800ms–60s")
    }
    @Test
    func permissionSummaryShowsAllStatusesInOneLine() {
        let snapshot = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: false,
            inputMonitoringGranted: false
        )
        #expect(UIStrings(language: .chinese).permissionSummary(snapshot) == "权限：✓ 麦克风 · × 辅助功能 · × 输入监控")
        #expect(UIStrings(language: .english).permissionSummary(snapshot) == "Permissions: ✓ Microphone · × Accessibility · × Input Monitoring")
        #expect(UIStrings(language: .chinese).permissionDetail("麦克风", granted: true) == "✓ 麦克风")
        #expect(UIStrings(language: .english).permissionDetail("Input Monitoring", granted: false) == "× Input Monitoring")

        let allTooltip = UIStrings(language: .chinese).tooltip(.requestAllPermissions)
        #expect(allTooltip.contains("麦克风"))
        #expect(allTooltip.contains("辅助功能"))
        #expect(allTooltip.contains("输入监控"))
        #expect(allTooltip.contains("系统弹窗"))
        #expect(UIStrings(language: .chinese).tooltip(.requestInputMonitoring).contains("/Applications/OmniVoice.app"))
        let userFacingTooltips = [
            allTooltip,
            UIStrings(language: .chinese).permissionUsageTooltip,
            UIStrings(language: .chinese).tooltip(.globalStop),
            UIStrings(language: .chinese).tooltip(.styleConcise),
            UIStrings(language: .chinese).tooltip(.styleVerbatim),
            UIStrings(language: .chinese).tooltip(.styleTechnical),
            UIStrings(language: .chinese).tooltip(.styleRewrite),
            UIStrings(language: .chinese).tooltip(.customStyles)
        ].joined(separator: "\n")
        #expect(!userFacingTooltips.localizedCaseInsensitiveContains("event tap"))
        #expect(!userFacingTooltips.localizedCaseInsensitiveContains("AX"))
        #expect(!userFacingTooltips.localizedCaseInsensitiveContains("TCC"))
        #expect(!userFacingTooltips.localizedCaseInsensitiveContains("bundle id"))
        #expect(!userFacingTooltips.contains("安全模式"))
        #expect(UIStrings(language: .chinese).tooltip(.requestMicrophone).contains("系统弹窗"))
    }
    @Test
    func connectionMessagesUseUserFacingLanguage() {
        let success = TestConnectionResult(
            selectedModel: AllowedSpeechModel.mimoV2Omni.rawValue,
            modelsReachable: true,
            selectedModelAllowed: true,
            audioProbeAccepted: true,
            audioProbeError: nil,
            message: "ok"
        )
        let text = UIStrings(language: .chinese).connectionCheckMessage(success)
        #expect(text.contains("可以使用"))
        #expect(!text.contains("探针"))
    }
    @Test
    func permissionGuidePlannerRequestsMissingPermissionsOnce() {
        let missingInput = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: false
        )
        #expect(PermissionGuidePlanner.actions(
            for: missingInput,
            hasRunStartupGuide: false,
            isManualRequest: false
        ) == [.requestInputMonitoring, .openInputMonitoringSettings])
        #expect(PermissionGuidePlanner.actions(
            for: missingInput,
            hasRunStartupGuide: true,
            isManualRequest: false
        ) == [])
        #expect(PermissionGuidePlanner.actions(
            for: missingInput,
            hasRunStartupGuide: true,
            isManualRequest: true
        ) == [.requestInputMonitoring, .openInputMonitoringSettings])
    }
    @Test
    func permissionReadinessAutoEnablesOnlyPermissionBlockedStops() {
        let missing = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: false
        )
        let ready = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: true
        )
        #expect(PermissionReadinessPlanner.shouldAutoEnable(
            previous: missing,
            current: ready,
            stopReason: .permissionBlocked
        ))
        #expect(!PermissionReadinessPlanner.shouldAutoEnable(
            previous: missing,
            current: ready,
            stopReason: .manual
        ))
        #expect(!PermissionReadinessPlanner.shouldAutoEnable(
            previous: missing,
            current: missing,
            stopReason: .permissionBlocked
        ))
        #expect(!PermissionReadinessPlanner.shouldAutoEnable(
            previous: ready,
            current: ready,
            stopReason: .permissionBlocked
        ))
    }
    @Test
    func listeningStartupRequiresPermissionsAndNoOtherInstance() {
        let ready = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: true
        )
        let missing = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: false
        )
        #expect(PermissionListeningStartupPlanner.shouldStartListening(
            listeningEnabled: true,
            globalStopActive: false,
            permissions: ready,
            hasOtherRunningInstance: false
        ))
        #expect(!PermissionListeningStartupPlanner.shouldStartListening(
            listeningEnabled: true,
            globalStopActive: false,
            permissions: missing,
            hasOtherRunningInstance: false
        ))
        #expect(!PermissionListeningStartupPlanner.shouldStartListening(
            listeningEnabled: true,
            globalStopActive: false,
            permissions: ready,
            hasOtherRunningInstance: true
        ))
        #expect(!PermissionListeningStartupPlanner.shouldStartListening(
            listeningEnabled: false,
            globalStopActive: false,
            permissions: ready,
            hasOtherRunningInstance: false
        ))
    }
    @Test
    func permissionDriftStopsOnlyWhenRunningPermissionsWereReady() {
        let ready = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: true
        )
        let missing = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: false,
            inputMonitoringGranted: true
        )
        #expect(PermissionDriftPlanner.shouldEnterPermissionBlockedStop(
            previous: ready,
            current: missing,
            listeningEnabled: true,
            globalStopActive: false
        ))
        #expect(!PermissionDriftPlanner.shouldEnterPermissionBlockedStop(
            previous: missing,
            current: missing,
            listeningEnabled: true,
            globalStopActive: false
        ))
        #expect(!PermissionDriftPlanner.shouldEnterPermissionBlockedStop(
            previous: ready,
            current: missing,
            listeningEnabled: false,
            globalStopActive: false
        ))
        #expect(!PermissionDriftPlanner.shouldEnterPermissionBlockedStop(
            previous: ready,
            current: missing,
            listeningEnabled: true,
            globalStopActive: true
        ))
    }
    @Test
    func singleInstancePlannerBlocksListeningWhenAnotherInstanceExists() {
        #expect(SingleInstanceLaunchPlanner.shouldAllowListening(otherRunningInstanceCount: 0))
        #expect(!SingleInstanceLaunchPlanner.shouldAllowListening(otherRunningInstanceCount: 1))
        #expect(!SingleInstanceLaunchPlanner.shouldAllowListening(otherRunningInstanceCount: 2))
    }
    @Test
    func tapDisabledRecoveryRequiresReadyPermissionsAndRunningState() {
        let ready = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: true
        )
        let missing = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: false
        )
        #expect(EventTapDisabledRecoveryPlanner.action(
            listeningEnabled: true,
            globalStopActive: false,
            permissions: ready
        ) == .restartListening)
        #expect(EventTapDisabledRecoveryPlanner.action(
            listeningEnabled: true,
            globalStopActive: false,
            permissions: missing
        ) == .enterPermissionBlockedStop)
        #expect(EventTapDisabledRecoveryPlanner.action(
            listeningEnabled: false,
            globalStopActive: false,
            permissions: ready
        ) == .stayStopped)
        #expect(EventTapDisabledRecoveryPlanner.action(
            listeningEnabled: true,
            globalStopActive: true,
            permissions: ready
        ) == .stayStopped)
    }
    @Test
    func startupAutoEnableRestoresOnlyPersistedPermissionBlockedStops() {
        let missing = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: false
        )
        let ready = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: true,
            inputMonitoringGranted: true
        )
        #expect(PermissionStartupAutoEnablePlanner.shouldAutoEnable(
            listeningEnabled: false,
            stopReason: .permissionBlocked,
            current: ready
        ))
        #expect(!PermissionStartupAutoEnablePlanner.shouldAutoEnable(
            listeningEnabled: false,
            stopReason: .manual,
            current: ready
        ))
        #expect(!PermissionStartupAutoEnablePlanner.shouldAutoEnable(
            listeningEnabled: false,
            stopReason: .previousRunRecovery,
            current: ready
        ))
        #expect(!PermissionStartupAutoEnablePlanner.shouldAutoEnable(
            listeningEnabled: false,
            stopReason: .permissionBlocked,
            current: missing
        ))
        #expect(!PermissionStartupAutoEnablePlanner.shouldAutoEnable(
            listeningEnabled: true,
            stopReason: .permissionBlocked,
            current: ready
        ))
    }
    @Test
    func legacyPermissionBlockedStopReasonIsInferredOnlyForStartupGuideStops() {
        #expect(PermissionLegacyStopReasonMigrationPlanner.inferredStopReason(
            listeningEnabled: false,
            storedStopReason: nil,
            didRunStartupPermissionGuide: true
        ) == .permissionBlocked)
        #expect(PermissionLegacyStopReasonMigrationPlanner.inferredStopReason(
            listeningEnabled: false,
            storedStopReason: .manual,
            didRunStartupPermissionGuide: true
        ) == .manual)
        #expect(PermissionLegacyStopReasonMigrationPlanner.inferredStopReason(
            listeningEnabled: false,
            storedStopReason: nil,
            didRunStartupPermissionGuide: false
        ) == nil)
        #expect(PermissionLegacyStopReasonMigrationPlanner.inferredStopReason(
            listeningEnabled: true,
            storedStopReason: nil,
            didRunStartupPermissionGuide: true
        ) == nil)
    }
    @Test
    func permissionGuideRunStateIsScopedToCurrentInstallIdentity() {
        #expect(PermissionGuideRunState(
            didRunStartupGuide: true,
            storedIdentity: "old-build",
            currentIdentity: "new-build"
        ).hasRunForCurrentIdentity == false)
        #expect(PermissionGuideRunState(
            didRunStartupGuide: true,
            storedIdentity: "same-build",
            currentIdentity: "same-build"
        ).hasRunForCurrentIdentity)
        #expect(PermissionGuideRunState(
            didRunStartupGuide: false,
            storedIdentity: "same-build",
            currentIdentity: "same-build"
        ).hasRunForCurrentIdentity == false)
    }
    @Test
    func permissionGuideIdentityPersistsInSettings() {
        let suiteName = "omnivoice-permission-identity-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        #expect(settings.startupPermissionGuideIdentity == nil)
        settings.startupPermissionGuideIdentity = "build-identity"
        #expect(settings.startupPermissionGuideIdentity == "build-identity")
    }
    @Test
    func stopReasonPersistsInSettings() {
        let suiteName = "omnivoice-stop-reason-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        #expect(settings.stopReason == nil)
        settings.stopReason = .permissionBlocked
        #expect(settings.stopReason == .permissionBlocked)
        settings.stopReason = nil
        #expect(settings.stopReason == nil)
    }
    @Test
    func runtimeActiveTriggersSafeModeOnNextLaunch() {
        let suiteName = "omnivoice-runtime-active-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        #expect(!settings.runtimeActive)
        #expect(!AppSafetyPlanner.shouldStartInSafeMode(previousRuntimeActive: settings.runtimeActive))

        settings.runtimeActive = true
        #expect(settings.runtimeActive)
        #expect(AppSafetyPlanner.shouldStartInSafeMode(previousRuntimeActive: settings.runtimeActive))
    }
}
