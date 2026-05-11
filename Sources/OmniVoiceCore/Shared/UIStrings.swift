import Foundation

public struct UIStrings: Sendable {
    public let language: UILanguage

    public init(language: UILanguage) {
        self.language = language
    }

    var stop: String { language == .chinese ? "停止" : "Stop" }
    var reenable: String { language == .chinese ? "重新启用" : "Re-enable" }
    var stopped: String { language == .chinese ? "已停止" : "Stopped" }
    var reenabled: String { language == .chinese ? "已重新启用" : "Re-enabled" }
    var stoppedAfterPreviousRun: String {
        language == .chinese ? "已停止：上次未正常退出" : "Stopped: previous run did not exit cleanly"
    }
    var statusPrefix: String { language == .chinese ? "状态" : "Status" }
    var baseURLPrefix: String { language == .chinese ? "Base URL" : "Base URL" }
    var apiKeyPrefix: String { language == .chinese ? "API Key" : "API Key" }
    var systemASRNoAPIBaseURL: String { language == .chinese ? "系统 ASR（不使用 API）" : "System ASR (no API)" }
    var apiKeyUnused: String { language == .chinese ? "未使用" : "not used" }
    var configured: String { language == .chinese ? "已配置" : "configured" }
    var missing: String { language == .chinese ? "缺失" : "missing" }
    var autoInsert: String { language == .chinese ? "自动插入" : "Auto Insert" }
    var reloadConfig: String { language == .chinese ? "重新加载配置" : "Reload Config" }
    var refreshModels: String { language == .chinese ? "刷新模型" : "Refresh Models" }
    var permissions: String { language == .chinese ? "权限" : "Permissions" }
    var configuration: String { language == .chinese ? "配置" : "Configuration" }
    var apiSource: String { language == .chinese ? "API 来源" : "API Source" }
    var modelConfiguration: String { language == .chinese ? "模型" : "Model" }
    var systemASR: String { language == .chinese ? "系统 ASR" : "System ASR" }
    var systemASREngine: String { language == .chinese ? "识别引擎" : "Recognition Engine" }
    var systemASRKeywordHints: String { language == .chinese ? "系统 ASR 关键词提示" : "System ASR Keyword Hints" }
    var noObservedModels: String { language == .chinese ? "刷新模型后可选择" : "Refresh models to choose" }
    var noLLMUsedForMode: String { language == .chinese ? "此模式不使用大模型" : "This mode does not use an LLM" }
    var editModelList: String { language == .chinese ? "编辑模型列表" : "Edit Model List" }
    var useSystemASROnly: String { language == .chinese ? "仅使用系统 ASR 能力" : "Use System ASR Only" }
    var latencyInterval: String { language == .chinese ? "测速频率" : "Latency Check" }
    var connectionLatencyCompleted: String { language == .chinese ? "连接检查与测速已完成" : "Connection and latency check complete" }
    var editCustomStyles: String { language == .chinese ? "打开 config.jsonc 编辑自定义风格" : "Open config.jsonc to edit custom styles" }
    var keywordHints: String { language == .chinese ? "关键词" : "Keyword Hints" }
    var enableKeywordHints: String { language == .chinese ? "启用关键词提示" : "Enable Keyword Hints" }
    var editKeywords: String { language == .chinese ? "打开 config 文件编辑关键词" : "Open config file to edit keywords" }
    var noKeywordGroups: String { language == .chinese ? "没有可用关键词组" : "No keyword groups available" }
    var openConfigFile: String { language == .chinese ? "打开 config 文件" : "Open config file" }
    var configFileOpened: String { language == .chinese ? "已打开 config 文件" : "Opened config file" }
    var configFileOpenedWithDefaultApp: String {
        language == .chinese
            ? "没有找到代码编辑器，已用系统默认应用打开 config 文件"
            : "No code editor was found; opened the config file with the system default app"
    }
    var configFileOpenFailed: String {
        language == .chinese ? "无法打开 config 文件" : "Could not open the config file"
    }
    func configFileOpenedInEditor(_ editor: String) -> String {
        language == .chinese ? "已用 \(editor) 打开 config 文件" : "Opened config file in \(editor)"
    }
    var operationFailed: String { language == .chinese ? "操作失败" : "Operation failed" }
    var launchAtLogin: String { language == .chinese ? "开机自启" : "Launch at Login" }
    var displayHints: String { language == .chinese ? "提示与显示" : "Display & Hints" }
    var hudStyle: String { language == .chinese ? "HUD 样式" : "HUD Style" }
    var hudMessageDuration: String { language == .chinese ? "提示显示时长" : "Message Duration" }
    var hudRevealDelay: String { language == .chinese ? "HUD 弹出延迟" : "HUD Reveal Delay" }
    var liveASRPreview: String { language == .chinese ? "实时 ASR 预览" : "Live ASR Preview" }
    var retry: String { language == .chinese ? "重试" : "Retry" }
    var requestFailed: String { language == .chinese ? "请求失败" : "Request Failed" }
    var recordTriggerKey: String { language == .chinese ? "录制触发键" : "Record Trigger Key" }
    var recordingTriggerKey: String { language == .chinese ? "请按一个可用触发键" : "Press an allowed trigger key" }
    var continuousRecordingDoubleTap: String { language == .chinese ? "双击持续录音" : "Double-tap Continuous Recording" }
    func continuousRecordingUnsupportedForTrigger(_ trigger: TriggerKey) -> String {
        language == .chinese
            ? "\(triggerLabel(trigger)) 暂不支持双击持续录音"
            : "\(triggerLabel(trigger)) does not support double-tap continuous recording yet"
    }
    var triggerRecordingHelp: String {
        language == .chinese
            ? "只接受 Fn/Globe、F1-F12、左右修饰键和 Caps Lock。Esc 取消。"
            : "Only Fn/Globe, F1-F12, left/right modifiers, and Caps Lock are accepted. Esc cancels."
    }
    var triggerRecordingRejected: String {
        language == .chinese ? "这个按键不能作为触发键" : "This key cannot be used as a trigger"
    }
    var restart: String { language == .chinese ? "重启" : "Restart" }
    var quit: String { language == .chinese ? "退出" : "Quit" }
    var restartFailed: String { language == .chinese ? "重启失败" : "Restart failed" }
    var requestAllPermissions: String { language == .chinese ? "请求所有权限" : "Request All Permissions" }
    var requestMicrophone: String { language == .chinese ? "请求麦克风权限" : "Request Microphone Permission" }
    var requestAccessibility: String { language == .chinese ? "请求辅助功能权限" : "Request Accessibility Permission" }
    var requestInputMonitoring: String { language == .chinese ? "请求输入监控权限" : "Request Input Monitoring Permission" }
    var requestSpeechRecognition: String { language == .chinese ? "请求语音识别权限" : "Request Speech Recognition Permission" }
    var permissionManagement: String { language == .chinese ? "权限管理" : "Permission Management" }
    var openMicrophoneSettings: String { language == .chinese ? "打开麦克风设置" : "Open Microphone Settings" }
    var openAccessibilitySettings: String { language == .chinese ? "打开辅助功能设置" : "Open Accessibility Settings" }
    var openInputMonitoringSettings: String { language == .chinese ? "打开输入监控设置" : "Open Input Monitoring Settings" }
    var openSpeechRecognitionSettings: String { language == .chinese ? "打开语音识别设置" : "Open Speech Recognition Settings" }
    var copy: String { language == .chinese ? "复制" : "Copy" }
    var cancel: String { language == .chinese ? "取消" : "Cancel" }
    var copied: String { language == .chinese ? "已复制" : "Copied" }
    public var listening: String { language == .chinese ? "正在聆听" : "Listening" }
    var transcribing: String { language == .chinese ? "正在转写" : "Transcribing" }
    var finishingRecognition: String { language == .chinese ? "正在完成识别" : "Finishing recognition" }
    var cancelled: String { language == .chinese ? "已取消" : "Cancelled" }
    var noTextRecognized: String { language == .chinese ? "没有识别到文本" : "No text recognized" }
    var noReliableSpeechRecognized: String {
        language == .chinese ? "没有识别到可靠语音，请重试" : "No reliable speech recognized; please try again"
    }
    var textLLMFailedTitle: String { language == .chinese ? "文本模型处理失败，以下是 ASR 草稿" : "Text model failed; ASR draft below" }
    var textLLMUnsupportedTitle: String {
        language == .chinese
            ? "当前文本模型可能不支持文本补全，请在 配置 > 模型 中更换模型。以下是 ASR 草稿"
            : "The current text model may not support text completion. Choose another model in Configuration > Model. ASR draft below"
    }
    var configReloaded: String { language == .chinese ? "配置已重新加载" : "Config reloaded" }
    var configHotReloaded: String { language == .chinese ? "配置已自动更新" : "Config updated automatically" }
    var modelsRefreshed: String { language == .chinese ? "模型列表已刷新" : "Models refreshed" }
    var permissionIssue: String { language == .chinese ? "监听异常，请检查权限" : "Listening unavailable; check permissions" }
    var eventTapWatchdogReset: String {
        language == .chinese ? "触发键状态已自动复位" : "Trigger state reset by watchdog"
    }
    var inputMonitoringManual: String {
        MenuTooltipCatalog.inputMonitoringManual(language: language)
    }
    var accessibilityManual: String {
        MenuTooltipCatalog.accessibilityManual(language: language)
    }
    func permissionSummary(_ snapshot: PermissionSnapshot) -> String {
        if language == .chinese {
            return "权限：\(permissionValue(snapshot.microphoneGranted)) 麦克风 · \(permissionValue(snapshot.accessibilityGranted)) 辅助功能 · \(permissionValue(snapshot.inputMonitoringGranted)) 输入监控 · \(permissionValue(snapshot.speechRecognitionGranted)) 语音识别"
        }
        return "Permissions: \(permissionValue(snapshot.microphoneGranted)) Microphone · \(permissionValue(snapshot.accessibilityGranted)) Accessibility · \(permissionValue(snapshot.inputMonitoringGranted)) Input Monitoring · \(permissionValue(snapshot.speechRecognitionGranted)) Speech Recognition"
    }

    func permissionValue(_ granted: Bool) -> String {
        granted ? "✓" : "×"
    }

    func permissionDetail(_ label: String, granted: Bool) -> String {
        "\(permissionValue(granted)) \(label)"
    }

    var permissionUsageTooltip: String {
        MenuTooltipCatalog.permissionUsage(language: language)
    }

    func statusIdle(listeningEnabled: Bool, tapStatus: String) -> String {
        listeningEnabled ? tapStatus : (language == .chinese ? "监听已停止" : "Listening stopped")
    }

    func statusRecording() -> String {
        language == .chinese ? "录音中" : "Recording"
    }

    func statusTranscribing() -> String {
        language == .chinese ? "转写中" : "Transcribing"
    }

    func listeningWithTrigger(_ trigger: TriggerKey) -> String {
        language == .chinese ? "监听中：\(triggerLabel(trigger))" : "Listening with \(triggerLabel(trigger))"
    }

    func listeningUnavailable() -> String {
        language == .chinese ? "监听不可用；请检查输入监控权限" : "Listening unavailable; check Input Monitoring"
    }

    func eventTapDisabled() -> String {
        language == .chinese ? "快捷键监听已停用" : "Shortcut listener disabled"
    }

    func modelTitle(_ model: AllowedSpeechModel) -> String {
        language == .chinese ? "模型：\(model.rawValue)" : "Model: \(model.rawValue)"
    }

    func systemASREngineTitle(_ engine: SystemASREngine) -> String {
        language == .chinese
            ? "识别引擎：\(engine.displayName(in: language))"
            : "Recognition Engine: \(engine.displayName(in: language))"
    }

    func transcriptionSummaryTitle(
        mode: TranscriptionPipelineMode,
        model: AllowedSpeechModel,
        engine: SystemASREngine? = nil
    ) -> String {
        if mode == .systemASROnly {
            let engineName = (engine ?? .defaultEngine).displayName(in: language)
            return language == .chinese
                ? "转写：仅系统 ASR · \(engineName)"
                : "Transcription: System ASR Only · \(engineName)"
        }
        return language == .chinese
            ? "转写：\(mode.displayName(in: language)) · \(model.rawValue)"
            : "Transcription: \(mode.displayName(in: language)) · \(model.rawValue)"
    }

    func modelConfigurationTitle(mode: TranscriptionPipelineMode, model: AllowedSpeechModel) -> String {
        if mode == .systemASROnly {
            return language == .chinese ? "模型：不使用大模型" : "Model: No LLM"
        }
        return language == .chinese
            ? "模型：\(mode.displayName(in: language)) · \(model.rawValue)"
            : "Model: \(mode.displayName(in: language)) · \(model.rawValue)"
    }

    func apiSourceDoesNotExposeCurrentModel(_ model: AllowedSpeechModel) -> String {
        MenuTooltipCatalog.apiSourceDoesNotExposeCurrentModel(model, language: language)
    }

    func systemASREngineTooltip(_ engine: SystemASREngine) -> String {
        MenuTooltipCatalog.systemASREngineTooltip(engine, language: language)
    }

    func modelMenuItem(_ model: AllowedSpeechModel, observed: Bool?) -> String {
        guard observed == false else { return model.rawValue }
        return language == .chinese
            ? "\(model.rawValue)（未在 /v1/models 观测到）"
            : "\(model.rawValue) (not observed in /v1/models)"
    }

    func uiLanguageTitle(_ uiLanguage: UILanguage) -> String {
        language == .chinese ? "语言：\(uiLanguage.displayName)" : "Language: \(uiLanguage.displayName)"
    }

    func styleTitle(_ style: TranscriptionStyle) -> String {
        language == .chinese ? "风格：\(style.displayName(in: language))" : "Style: \(style.displayName(in: language))"
    }

    func styleTitle(_ descriptor: TranscriptionStyleDescriptor) -> String {
        let name = styleMenuItem(descriptor)
        return language == .chinese ? "风格：\(name)" : "Style: \(name)"
    }

    func styleMenuItem(_ descriptor: TranscriptionStyleDescriptor) -> String {
        let name = descriptor.localizedName(in: language)
        guard descriptor.isCustom else { return name }
        return language == .chinese ? "\(name)（自定义）" : "\(name) (Custom)"
    }

    func keywordHintsTitle(enabled: Bool, selectedCount: Int) -> String {
        let state: String
        if enabled {
            state = selectedCount > 0
                ? (language == .chinese ? "\(selectedCount) 组" : "\(selectedCount) groups")
                : (language == .chinese ? "未选择" : "none")
        } else {
            state = language == .chinese ? "未启用" : "not enabled"
        }
        return language == .chinese ? "关键词：\(state)" : "Keyword Hints: \(state)"
    }

    func keywordGroupMenuItem(_ group: KeywordGroup) -> String {
        group.localizedName(in: language)
    }

    func configHotReloadInvalidExported(_ path: String) -> String {
        language == .chinese
            ? "配置文件有问题，当前配置已导出到 \(path)"
            : "The config file has a problem; the current config was exported to \(path)"
    }

    func panelStyleSwitchTitle(_ descriptor: TranscriptionStyleDescriptor) -> String {
        language == .chinese
            ? "风格：\(descriptor.localizedName(in: language))"
            : "Style: \(descriptor.localizedName(in: language))"
    }

    func triggerTitle(_ trigger: TriggerKey) -> String {
        language == .chinese ? "触发键：\(triggerLabel(trigger))" : "Trigger: \(triggerLabel(trigger))"
    }

    func recordingDurationTitle(min: MinRecordingDuration, max: MaxRecordingDuration) -> String {
        language == .chinese
            ? "录音时长：\(min.displayName)–\(max.displayName)"
            : "Duration: \(min.displayName)–\(max.displayName)"
    }

    var minRecordingDuration: String {
        language == .chinese ? "最短录音" : "Minimum Recording"
    }

    var maxRecordingDuration: String {
        language == .chinese ? "最长录音" : "Maximum Recording"
    }

    func hudStyleTitle(_ style: HUDVisualStyle) -> String {
        language == .chinese ? "HUD 样式：\(style.displayName(in: language))" : "HUD Style: \(style.displayName(in: language))"
    }

    func hudMessageDurationTitle(_ duration: HUDMessageDuration) -> String {
        language == .chinese ? "提示显示时长：\(duration.displayName)" : "Message Duration: \(duration.displayName)"
    }

    func hudRevealDelayTitle(_ delay: HUDRevealDelay) -> String {
        language == .chinese
            ? "HUD 弹出延迟：\(delay.displayName(in: language))"
            : "HUD Reveal Delay: \(delay.displayName(in: language))"
    }

    func liveASRPreviewTitle(enabled: Bool) -> String {
        language == .chinese
            ? "实时 ASR 预览：\(enabled ? "开" : "关")"
            : "Live ASR Preview: \(enabled ? "on" : "off")"
    }

    public var liveASRPreviewBadge: String {
        language == .chinese ? "草稿" : "Draft"
    }

    var liveASRRecognitionBadge: String {
        language == .chinese ? "识别" : "Live"
    }

    func triggerLabel(_ trigger: TriggerKey) -> String {
        guard language == .chinese else { return trigger.displayLabel }
        switch trigger.identifier {
        case "fn-globe": return "Fn/Globe"
        case "modifier-left-shift": return "左 Shift"
        case "modifier-right-shift": return "右 Shift"
        case "modifier-left-control": return "左 Control"
        case "modifier-right-control": return "右 Control"
        case "modifier-left-option": return "左 Option"
        case "modifier-right-option": return "右 Option"
        case "modifier-left-command": return "左 Command"
        case "modifier-right-command": return "右 Command"
        case "caps-lock": return "Caps Lock"
        default: return trigger.displayLabel
        }
    }

    func connectionCheckDefault() -> String {
        language == .chinese ? "检查连接与测速" : "Check Connection & Latency"
    }

    func connectionCheckRunning() -> String {
        language == .chinese ? "检查连接与测速：运行中..." : "Check Connection & Latency: running..."
    }

    func connectionCheckMessage(_ result: TestConnectionResult) -> String {
        guard result.modelsReachable else {
            return language == .chinese ? "连接失败：\(result.message)" : "Connection failed: \(result.message)"
        }
        guard result.selectedModelAllowed else {
            return language == .chinese
                ? "连接可用；当前模型不能用于语音识别"
                : "Connection OK; selected model cannot transcribe speech"
        }
        if result.message.contains("not observed") || result.message.contains("not exposed") {
            return language == .chinese
                ? "连接可用；当前来源没有列出 \(result.selectedModel)"
                : "Connection OK; the current source does not list \(result.selectedModel)"
        }
        return language == .chinese
            ? "连接可用；\(result.selectedModel) 可以使用"
            : "Connection OK; \(result.selectedModel) is available"
    }

    func transcriptionStyleTooltip(_ descriptor: TranscriptionStyleDescriptor) -> String {
        MenuTooltipCatalog.transcriptionStyleTooltip(descriptor, language: language)
    }

    func tooltip(_ key: MenuTooltipKey) -> String {
        MenuTooltipCatalog.tooltip(key, language: language)
    }
}
