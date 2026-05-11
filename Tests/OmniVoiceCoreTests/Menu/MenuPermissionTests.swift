import Foundation
import Testing
@testable import OmniVoiceCore

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
            prompt: "整理成会议纪要"
        )
        let customDescriptor = TranscriptionStyleResolver.resolve(
            selection: .custom("meeting_notes"),
            customStyles: [custom]
        )
        #expect(MenuTitleFormatter.style(customDescriptor, uiLanguage: .chinese) == "风格：Meeting Notes（自定义）")
        #expect(UIStrings(language: .english).panelStyleSwitchTitle(customDescriptor) == "Style: Meeting Notes")
        #expect(UIStrings(language: .chinese).apiSourceTitle(MimoConfig(activeSourceID: "sgp")).contains("sgp"))
        #expect(UIStrings(language: .english).latencyIntervalTitle(.minutes30) == "Latency Check: Every 30 minutes")
        #expect(UIStrings(language: .chinese).latencyIntervalLabel(.seconds30) == "每 30 秒")
        #expect(ConfigLatencyInterval.allCases.map(\.rawValue) == [30, 60, 120, 300, 900, 1800, 3600, 0, -1])
        #expect(UIStrings(language: .chinese).displayHints == "提示与显示")
        #expect(UIStrings(language: .english).displayHints == "Display & Hints")
        #expect(UIStrings(language: .chinese).liveASRPreviewTitle(enabled: true) == "实时 ASR 预览：开")
        #expect(UIStrings(language: .chinese).liveASRPreviewBadge == "草稿")
        #expect(UIStrings(language: .chinese).liveASRRecognitionBadge == "识别")
        #expect(UIStrings(language: .english).liveASRPreviewBadge == "Draft")
        #expect(UIStrings(language: .english).liveASRRecognitionBadge == "Live")
        #expect(UIStrings(language: .english).tooltip(.liveASRPreview).contains("local Direct Audio quality checks"))
        #expect(UIStrings(language: .chinese).hudRevealDelayTitle(.milliseconds200) == "HUD 弹出延迟：200ms · 快速（推荐）")
        #expect(UIStrings(language: .english).hudRevealDelayTitle(.milliseconds500) == "HUD Reveal Delay: 500ms · Most Conservative")
        #expect(UIStrings(language: .chinese).configurationTitle(MimoConfig(apiKey: nil, source: .missing)).contains("缺少 API Key"))
        #expect(UIStrings(language: .chinese).apiKeyStatus(MimoConfig(apiKey: nil)) == "缺失")
        #expect(UIStrings(language: .chinese).configWarning("Config warning: config.jsonc could not be read").contains("无法读取"))
        #expect(UIStrings(language: .chinese).permissionManagement == "权限管理")
        #expect(UIStrings(language: .chinese).stop == "停止")
        #expect(UIStrings(language: .chinese).reenable == "重新启用")
        #expect(UIStrings(language: .chinese).openConfigFile == "打开 config 文件")
        #expect(UIStrings(language: .english).openConfigFile == "Open config file")
        #expect(UIStrings(language: .chinese).continuousRecordingDoubleTap == "双击持续录音")
        #expect(UIStrings(language: .english).continuousRecordingUnsupportedForTrigger(.capsLock).contains("Caps Lock"))
        #expect(UIStrings(language: .chinese).tooltip(.continuousRecordingDoubleTap).contains("再次单击"))
        #expect(UIStrings(language: .chinese).requestSpeechRecognition == "请求语音识别权限")
        #expect(UIStrings(language: .chinese).finishingRecognition == "正在完成识别")
        #expect(UIStrings(language: .english).finishingRecognition == "Finishing recognition")
        #expect(UIStrings(language: .english).openSpeechRecognitionSettings == "Open Speech Recognition Settings")
        #expect(UIStrings(language: .chinese).pipelineModeTitle(.systemASRTextLLM) == "转写模式：语音识别 + 文本转写")
        #expect(UIStrings(language: .chinese).pipelineModeTitle(.systemASROnly) == "转写模式：仅系统 ASR")
        #expect(UIStrings(language: .chinese).transcriptionSummaryTitle(mode: .inputAudio, model: .mimoV25) == "转写：音频直转 · mimo-v2.5")
        #expect(UIStrings(language: .chinese).transcriptionSummaryTitle(
            mode: .systemASROnly,
            model: .mimoV25,
            engine: .classicSpeech
        ) == "转写：仅系统 ASR · 经典 Speech")
        #expect(UIStrings(language: .english).modelConfigurationTitle(mode: .systemASRTextLLM, model: .mimoV25).contains("Speech Recognition + Text Rewrite"))
        #expect(UIStrings(language: .chinese).modelConfigurationTitle(mode: .systemASROnly, model: .mimoV25) == "模型：不使用大模型")
        #expect(UIStrings(language: .chinese).apiSourceTitle(
            MimoConfig(activeSourceID: "sgp", pipelineMode: .systemASROnly),
            mode: .systemASROnly
        ) == "API 来源：仅系统 ASR")
        #expect(UIStrings(language: .english).inputAudioModelTitle(.mimoV2Omni) == "Input Audio Model: mimo-v2-omni")
        #expect(UIStrings(language: .chinese).textLLMModelTitle(.mimoV25) == "文本模型：mimo-v2.5")
        #expect(UIStrings(language: .english).systemASREngineTitle(.classicSpeech) == "Recognition Engine: Classic Speech")
        #expect(UIStrings(language: .chinese).systemASREngineTitle(.appleOnlineSpeech) == "识别引擎：Apple 在线识别")
        #expect(UIStrings(language: .chinese).systemASRNoAPIBaseURL == "系统 ASR（不使用 API）")
        #expect(UIStrings(language: .chinese).apiKeyUnused == "未使用")
        #expect(UIStrings(language: .chinese).noLLMUsedForMode == "此模式不使用大模型")
        #expect(UIStrings(language: .chinese).useSystemASROnly == "仅使用系统 ASR 能力")
        #expect(UIStrings(language: .chinese).noObservedModels == "刷新模型后可选择")
        #expect(UIStrings(language: .chinese).editModelList == "编辑模型列表")
        #expect(UIStrings(language: .english).editModelList == "Edit Model List")
        #expect(UIStrings(language: .english).tooltip(.editModelList).contains("Audio LLM"))
        #expect(UIStrings(language: .english).tooltip(.editModelList).contains("models endpoint"))
        #expect(UIStrings(language: .chinese).tooltip(.systemASROnlyMode).contains("不调用模型 API"))
        #expect(UIStrings(language: .chinese).textLLMUnsupportedTitle.contains("更换模型"))
        #expect(UIStrings(language: .chinese).apiSourceDoesNotExposeCurrentModel(.mimoV25).contains("mimo-v2.5"))
        #expect(UIStrings(language: .chinese).keywordHintsTitle(enabled: true, selectedCount: 2) == "关键词：2 组")
        #expect(UIStrings(language: .chinese).keywordHintsTitle(enabled: false, selectedCount: 2) == "关键词：未启用")
        #expect(UIStrings(language: .english).keywordHintsTitle(enabled: false, selectedCount: 2) == "Keyword Hints: not enabled")
        #expect(UIStrings(language: .chinese).enableKeywordHints == "启用关键词提示")
        #expect(UIStrings(language: .english).editKeywords == "Open config file to edit keywords")
        let keywordGroup = KeywordGroup(id: "terms", displayName: "Terms", keywords: ["OmniVoice"])
        #expect(UIStrings(language: .english).keywordGroupMenuItem(keywordGroup) == "Terms")
        #expect(UIStrings(language: .chinese).restart == "重启")
        #expect(UIStrings(language: .chinese).quit == "退出")
        #expect(UIStrings(language: .english).restart == "Restart")
        #expect(UIStrings(language: .english).quit == "Quit")
        #expect(UIStrings(language: .chinese).recordingDurationTitle(min: .milliseconds800, max: .seconds60) == "录音时长：800ms–60s")
    }
    @Test
    func permissionSummaryShowsAllStatusesInOneLine() {
        let snapshot = PermissionSnapshot(
            microphoneGranted: true,
            accessibilityGranted: false,
            inputMonitoringGranted: false,
            speechRecognitionGranted: false
        )
        #expect(UIStrings(language: .chinese).permissionSummary(snapshot) == "权限：✓ 麦克风 · × 辅助功能 · × 输入监控 · × 语音识别")
        #expect(UIStrings(language: .english).permissionSummary(snapshot) == "Permissions: ✓ Microphone · × Accessibility · × Input Monitoring · × Speech Recognition")
        #expect(UIStrings(language: .chinese).permissionDetail("麦克风", granted: true) == "✓ 麦克风")
        #expect(UIStrings(language: .english).permissionDetail("Input Monitoring", granted: false) == "× Input Monitoring")

        let allTooltip = UIStrings(language: .chinese).tooltip(.requestAllPermissions)
        #expect(allTooltip.contains("麦克风"))
        #expect(allTooltip.contains("辅助功能"))
        #expect(allTooltip.contains("输入监控"))
        #expect(allTooltip.contains("语音识别"))
        #expect(allTooltip.contains("系统弹窗"))
        #expect(UIStrings(language: .chinese).tooltip(.requestInputMonitoring).contains("/Applications/OmniVoice.app"))
        #expect(UIStrings(language: .chinese).tooltip(.requestAccessibility).contains("系统设置"))
        #expect(UIStrings(language: .chinese).accessibilityManual.contains("去系统设置"))
        #expect(UIStrings(language: .chinese).accessibilityManual.contains("开启 OmniVoice"))
        #expect(UIStrings(language: .chinese).tooltip(.requestSpeechRecognition).contains("系统弹窗"))
        #expect(UIStrings(language: .chinese).tooltip(.requestSpeechRecognition).contains("音频直转"))
        let userFacingTooltips = [
            allTooltip,
            UIStrings(language: .chinese).permissionUsageTooltip,
            UIStrings(language: .chinese).tooltip(.globalStop),
            UIStrings(language: .chinese).tooltip(.styleConcise),
            UIStrings(language: .chinese).tooltip(.styleVerbatim),
            UIStrings(language: .chinese).tooltip(.styleTechnical),
            UIStrings(language: .chinese).tooltip(.styleRewrite),
            UIStrings(language: .chinese).tooltip(.customStyles),
            UIStrings(language: .chinese).tooltip(.keywordHints),
            UIStrings(language: .chinese).tooltip(.transcriptionMode),
            UIStrings(language: .chinese).tooltip(.inputAudioModel),
            UIStrings(language: .chinese).tooltip(.textLLMModel),
            UIStrings(language: .chinese).tooltip(.requestSpeechRecognition),
            UIStrings(language: .chinese).systemASREngineTooltip(.appleOnlineSpeech),
            UIStrings(language: .chinese).tooltip(.displayHints),
            UIStrings(language: .chinese).tooltip(.continuousRecordingDoubleTap),
            UIStrings(language: .chinese).tooltip(.hudRevealDelay)
        ].joined(separator: "\n")
        #expect(!userFacingTooltips.localizedCaseInsensitiveContains("event tap"))
        #expect(!userFacingTooltips.localizedCaseInsensitiveContains("AX"))
        #expect(!userFacingTooltips.localizedCaseInsensitiveContains("TCC"))
        #expect(!userFacingTooltips.localizedCaseInsensitiveContains("bundle id"))
        #expect(!userFacingTooltips.contains("安全模式"))
        #expect(UIStrings(language: .chinese).tooltip(.requestMicrophone).contains("系统弹窗"))
    }

    @Test
    func menuTooltipCatalogCoversEveryStableKey() {
        for key in MenuTooltipKey.allCases {
            #expect(!UIStrings(language: .chinese).tooltip(key).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!UIStrings(language: .english).tooltip(key).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        let allUserFacingText = MenuTooltipKey.allCases.flatMap { key in
            [
                UIStrings(language: .chinese).tooltip(key),
                UIStrings(language: .english).tooltip(key)
            ]
        } + SystemASREngine.allCases.flatMap { engine in
            [
                UIStrings(language: .chinese).systemASREngineTooltip(engine),
                UIStrings(language: .english).systemASREngineTooltip(engine)
            ]
        } + [
            UIStrings(language: .chinese).permissionUsageTooltip,
            UIStrings(language: .english).permissionUsageTooltip
        ]

        let joined = allUserFacingText.joined(separator: "\n")
        #expect(!joined.localizedCaseInsensitiveContains("event tap"))
        #expect(!joined.localizedCaseInsensitiveContains("TCC"))
        #expect(!joined.localizedCaseInsensitiveContains("bundle id"))
        #expect(!joined.localizedCaseInsensitiveContains("AX"))
    }

    @Test
    func permissionTooltipsNameTheSmallGuidanceDialogAndOtherSpaces() {
        let accessibilityCN = UIStrings(language: .chinese).tooltip(.requestAccessibility)
        let inputMonitoringCN = UIStrings(language: .chinese).tooltip(.requestInputMonitoring)
        #expect(accessibilityCN.contains("权限引导小对话框"))
        #expect(inputMonitoringCN.contains("权限引导小对话框"))
        #expect(accessibilityCN.contains("其他 Space"))
        #expect(accessibilityCN.contains("Mission Control"))
        #expect(accessibilityCN.contains("Cmd+Tab"))

        let accessibilityEN = UIStrings(language: .english).tooltip(.requestAccessibility)
        #expect(accessibilityEN.contains("permission guidance dialog"))
        #expect(accessibilityEN.contains("another Space"))
        #expect(accessibilityEN.contains("Mission Control"))
        #expect(accessibilityEN.contains("Cmd+Tab"))
    }

    @Test
    func parentMenuTooltipsDoNotDuplicateChildActions() {
        let strings = UIStrings(language: .chinese)
        #expect(strings.tooltip(.configuration) != strings.tooltip(.openConfigFile))
        #expect(strings.tooltip(.configuration) != strings.tooltip(.reloadConfig))
        #expect(strings.tooltip(.systemASR) != strings.tooltip(.systemASREngine))
        #expect(strings.tooltip(.systemASR) != strings.systemASREngineTooltip(.speechAnalyzer))
        #expect(strings.tooltip(.displayHints) != strings.tooltip(.liveASRPreview))
        #expect(strings.tooltip(.displayHints) != strings.tooltip(.hudRevealDelay))
        #expect(strings.tooltip(.apiSourceAvailable) != strings.apiSourceDoesNotExposeCurrentModel(.mimoV25))
    }

    @Test
    func systemSettingsActivationPlanIsBestEffortAndDeterministic() {
        #expect(SystemSettingsActivationPlanner.bundleIdentifier == "com.apple.systempreferences")
        #expect(SystemSettingsActivationPlanner.activationDelays == [0.2, 0.8])
    }

    @Test
    func systemASRAvailabilityAndSpeechAnalyzerPreflightAreExplicit() {
        #expect(SystemASREngineAvailabilityResolver.speechAnalyzerAvailable(osMajorVersion: 26))
        #expect(!SystemASREngineAvailabilityResolver.speechAnalyzerAvailable(osMajorVersion: 15))
        #expect(SystemASREngineAvailabilityResolver.effectiveEngine(
            configured: .speechAnalyzer,
            osMajorVersion: 15
        ) == .classicSpeech)
        #expect(SystemASREngineAvailabilityResolver.effectiveEngine(
            configured: .appleOnlineSpeech,
            osMajorVersion: 15
        ) == .appleOnlineSpeech)
        #expect(SpeechAnalyzerPreflightPlanner.action(for: .installed) == .ready)
        #expect(SpeechAnalyzerPreflightPlanner.action(for: .supported) == .prepareAssets)
        #expect(SpeechAnalyzerPreflightPlanner.action(for: .downloading) == .prepareAssets)
        #expect(SpeechAnalyzerPreflightPlanner.action(for: .unsupported) == .unavailable)
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
    func singleInstancePlannerBlocksListeningWhenAnotherInstanceExists() {
        #expect(SingleInstanceLaunchPlanner.shouldAllowListening(otherRunningInstanceCount: 0))
        #expect(!SingleInstanceLaunchPlanner.shouldAllowListening(otherRunningInstanceCount: 1))
        #expect(!SingleInstanceLaunchPlanner.shouldAllowListening(otherRunningInstanceCount: 2))
    }

    @Test
    func singleInstancePlannerAllowsListeningAfterOldInstanceExits() {
        let resolved = SingleInstanceResolution(observedCount: 1, remainingCount: 0)
        let blocked = SingleInstanceResolution(observedCount: 1, remainingCount: 1)

        #expect(SingleInstanceLaunchPlanner.shouldAllowListening(resolution: resolved))
        #expect(!SingleInstanceLaunchPlanner.shouldAllowListening(resolution: blocked))
        #expect(!resolved.hasConflict)
        #expect(blocked.hasConflict)
    }

    @Test
    func settingsDefaultsUseChineseUIAndAutoInsert() {
        let suiteName = "omnivoice-defaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        #expect(defaults.string(forKey: SettingsStore.Key.uiLanguage) == UILanguage.defaultLanguage.rawValue)
        #expect(settings.uiLanguage == .chinese)
        #expect(settings.autoInsert)
        #expect(settings.transcriptionStyleSelection == .builtIn(.rewrite))
        #expect(!settings.keywordHintsEnabled)
        #expect(settings.enabledKeywordGroupIDs.isEmpty)
        #expect(settings.systemASREngine == .speechAnalyzer)
        #expect(settings.maxRecordingDuration == .seconds120)
        #expect(settings.hudRevealDelay == .milliseconds100)
    }

    @Test
    func keywordGroupSelectionAutoEnablesAndDisablesHints() {
        let availableIDs = ["omnivoice_terms", "technical_terms"]
        let first = KeywordHintSelectionPlanner.toggleGroup(
            "omnivoice_terms",
            selectedIDs: [],
            availableIDs: availableIDs
        )
        #expect(first.isEnabled)
        #expect(first.selectedIDs == ["omnivoice_terms"])

        let second = KeywordHintSelectionPlanner.toggleGroup(
            "technical_terms",
            selectedIDs: ["omnivoice_terms", "omnivoice_terms", "bad group", "deleted_terms"],
            availableIDs: availableIDs
        )
        #expect(second.isEnabled)
        #expect(second.selectedIDs == ["omnivoice_terms", "technical_terms"])

        let remaining = KeywordHintSelectionPlanner.toggleGroup(
            "omnivoice_terms",
            selectedIDs: ["omnivoice_terms", "technical_terms"],
            availableIDs: availableIDs
        )
        #expect(remaining.isEnabled)
        #expect(remaining.selectedIDs == ["technical_terms"])

        let empty = KeywordHintSelectionPlanner.toggleGroup(
            "technical_terms",
            selectedIDs: ["technical_terms"],
            availableIDs: availableIDs
        )
        #expect(!empty.isEnabled)
        #expect(empty.selectedIDs.isEmpty)

        let disabledWithNoSelection = KeywordHintSelectionPlanner.toggleEnabled(
            isEnabled: false,
            selectedIDs: [],
            availableIDs: availableIDs
        )
        #expect(!disabledWithNoSelection.isEnabled)
        #expect(disabledWithNoSelection.selectedIDs.isEmpty)

        let disabledWithSelection = KeywordHintSelectionPlanner.toggleEnabled(
            isEnabled: false,
            selectedIDs: ["technical_terms"],
            availableIDs: availableIDs
        )
        #expect(disabledWithSelection.isEnabled)
        #expect(disabledWithSelection.selectedIDs == ["technical_terms"])

        let turnedOff = KeywordHintSelectionPlanner.toggleEnabled(
            isEnabled: true,
            selectedIDs: ["technical_terms"],
            availableIDs: availableIDs
        )
        #expect(!turnedOff.isEnabled)
        #expect(turnedOff.selectedIDs.isEmpty)
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
