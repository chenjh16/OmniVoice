import Foundation

public struct UIStrings: Sendable {
    public let language: UILanguage

    public init(language: UILanguage) {
        self.language = language
    }

    public var stop: String { language == .chinese ? "停止" : "Stop" }
    public var reenable: String { language == .chinese ? "重新启用" : "Re-enable" }
    public var stopped: String { language == .chinese ? "已停止" : "Stopped" }
    public var reenabled: String { language == .chinese ? "已重新启用" : "Re-enabled" }
    public var stoppedAfterPreviousRun: String {
        language == .chinese ? "已停止：上次未正常退出" : "Stopped: previous run did not exit cleanly"
    }
    public var statusPrefix: String { language == .chinese ? "状态" : "Status" }
    public var baseURLPrefix: String { language == .chinese ? "Base URL" : "Base URL" }
    public var apiKeyPrefix: String { language == .chinese ? "API Key" : "API Key" }
    public var systemASRNoAPIBaseURL: String { language == .chinese ? "系统 ASR（不使用 API）" : "System ASR (no API)" }
    public var apiKeyUnused: String { language == .chinese ? "未使用" : "not used" }
    public var configured: String { language == .chinese ? "已配置" : "configured" }
    public var missing: String { language == .chinese ? "缺失" : "missing" }
    public var autoInsert: String { language == .chinese ? "自动插入" : "Auto Insert" }
    public var reloadConfig: String { language == .chinese ? "重新加载配置" : "Reload Config" }
    public var refreshModels: String { language == .chinese ? "刷新模型" : "Refresh Models" }
    public var permissions: String { language == .chinese ? "权限" : "Permissions" }
    public var configuration: String { language == .chinese ? "配置" : "Configuration" }
    public var apiSource: String { language == .chinese ? "API 来源" : "API Source" }
    public var modelConfiguration: String { language == .chinese ? "模型" : "Model" }
    public var transcriptionMode: String { language == .chinese ? "转写模式" : "Transcription Mode" }
    public var inputAudioModel: String { language == .chinese ? "音频模型" : "Input Audio Model" }
    public var textLLMModel: String { language == .chinese ? "文本模型" : "Text LLM Model" }
    public var systemASR: String { language == .chinese ? "系统 ASR" : "System ASR" }
    public var systemASREngine: String { language == .chinese ? "识别引擎" : "Recognition Engine" }
    public var systemASRKeywordHints: String { language == .chinese ? "系统 ASR 关键词提示" : "System ASR Keyword Hints" }
    public var noObservedModels: String { language == .chinese ? "刷新模型后可选择" : "Refresh models to choose" }
    public var noLLMUsedForMode: String { language == .chinese ? "此模式不使用大模型" : "This mode does not use an LLM" }
    public var editModelList: String { language == .chinese ? "编辑模型列表" : "Edit Model List" }
    public var useSystemASROnly: String { language == .chinese ? "仅使用系统 ASR 能力" : "Use System ASR Only" }
    public var latencyInterval: String { language == .chinese ? "测速频率" : "Latency Check" }
    public var connectionLatencyCompleted: String { language == .chinese ? "连接检查与测速已完成" : "Connection and latency check complete" }
    public var editCustomStyles: String { language == .chinese ? "打开 config.jsonc 编辑自定义风格" : "Open config.jsonc to edit custom styles" }
    public var keywordHints: String { language == .chinese ? "关键词" : "Keyword Hints" }
    public var enableKeywordHints: String { language == .chinese ? "启用关键词提示" : "Enable Keyword Hints" }
    public var editKeywords: String { language == .chinese ? "打开 config 文件编辑关键词" : "Open config file to edit keywords" }
    public var noKeywordGroups: String { language == .chinese ? "没有可用关键词组" : "No keyword groups available" }
    public var openConfigFile: String { language == .chinese ? "打开 config 文件" : "Open config file" }
    public var configFileOpened: String { language == .chinese ? "已打开 config 文件" : "Opened config file" }
    public var configFileOpenedWithDefaultApp: String {
        language == .chinese
            ? "没有找到代码编辑器，已用系统默认应用打开 config 文件"
            : "No code editor was found; opened the config file with the system default app"
    }
    public var configFileOpenFailed: String {
        language == .chinese ? "无法打开 config 文件" : "Could not open the config file"
    }
    public func configFileOpenedInEditor(_ editor: String) -> String {
        language == .chinese ? "已用 \(editor) 打开 config 文件" : "Opened config file in \(editor)"
    }
    public var operationFailed: String { language == .chinese ? "操作失败" : "Operation failed" }
    public var launchAtLogin: String { language == .chinese ? "开机自启" : "Launch at Login" }
    public var displayHints: String { language == .chinese ? "提示与显示" : "Display & Hints" }
    public var hudStyle: String { language == .chinese ? "HUD 样式" : "HUD Style" }
    public var hudMessageDuration: String { language == .chinese ? "提示显示时长" : "Message Duration" }
    public var hudRevealDelay: String { language == .chinese ? "HUD 弹出延迟" : "HUD Reveal Delay" }
    public var liveASRPreview: String { language == .chinese ? "实时 ASR 预览" : "Live ASR Preview" }
    public var retry: String { language == .chinese ? "重试" : "Retry" }
    public var requestFailed: String { language == .chinese ? "请求失败" : "Request Failed" }
    public var recordTriggerKey: String { language == .chinese ? "录制触发键" : "Record Trigger Key" }
    public var recordingTriggerKey: String { language == .chinese ? "请按一个可用触发键" : "Press an allowed trigger key" }
    public var continuousRecordingDoubleTap: String { language == .chinese ? "双击持续录音" : "Double-tap Continuous Recording" }
    public func continuousRecordingUnsupportedForTrigger(_ trigger: TriggerKey) -> String {
        language == .chinese
            ? "\(triggerLabel(trigger)) 暂不支持双击持续录音"
            : "\(triggerLabel(trigger)) does not support double-tap continuous recording yet"
    }
    public var triggerRecordingHelp: String {
        language == .chinese
            ? "只接受 Fn/Globe、F1-F12、左右修饰键和 Caps Lock。Esc 取消。"
            : "Only Fn/Globe, F1-F12, left/right modifiers, and Caps Lock are accepted. Esc cancels."
    }
    public var triggerRecordingRejected: String {
        language == .chinese ? "这个按键不能作为触发键" : "This key cannot be used as a trigger"
    }
    public var restart: String { language == .chinese ? "重启" : "Restart" }
    public var quit: String { language == .chinese ? "退出" : "Quit" }
    public var restartFailed: String { language == .chinese ? "重启失败" : "Restart failed" }
    public var requestAllPermissions: String { language == .chinese ? "请求所有权限" : "Request All Permissions" }
    public var requestMicrophone: String { language == .chinese ? "请求麦克风权限" : "Request Microphone Permission" }
    public var requestAccessibility: String { language == .chinese ? "请求辅助功能权限" : "Request Accessibility Permission" }
    public var requestInputMonitoring: String { language == .chinese ? "请求输入监控权限" : "Request Input Monitoring Permission" }
    public var requestSpeechRecognition: String { language == .chinese ? "请求语音识别权限" : "Request Speech Recognition Permission" }
    public var permissionManagement: String { language == .chinese ? "权限管理" : "Permission Management" }
    public var openMicrophoneSettings: String { language == .chinese ? "打开麦克风设置" : "Open Microphone Settings" }
    public var openAccessibilitySettings: String { language == .chinese ? "打开辅助功能设置" : "Open Accessibility Settings" }
    public var openInputMonitoringSettings: String { language == .chinese ? "打开输入监控设置" : "Open Input Monitoring Settings" }
    public var openSpeechRecognitionSettings: String { language == .chinese ? "打开语音识别设置" : "Open Speech Recognition Settings" }
    public var copy: String { language == .chinese ? "复制" : "Copy" }
    public var cancel: String { language == .chinese ? "取消" : "Cancel" }
    public var copied: String { language == .chinese ? "已复制" : "Copied" }
    public var listening: String { language == .chinese ? "正在聆听" : "Listening" }
    public var transcribing: String { language == .chinese ? "正在转写" : "Transcribing" }
    public var finishingRecognition: String { language == .chinese ? "正在完成识别" : "Finishing recognition" }
    public var cancelled: String { language == .chinese ? "已取消" : "Cancelled" }
    public var noTextRecognized: String { language == .chinese ? "没有识别到文本" : "No text recognized" }
    public var textLLMFailedTitle: String { language == .chinese ? "文本模型处理失败，以下是 ASR 草稿" : "Text model failed; ASR draft below" }
    public var textLLMUnsupportedTitle: String {
        language == .chinese
            ? "当前文本模型可能不支持文本补全，请在 配置 > 模型 中更换模型。以下是 ASR 草稿"
            : "The current text model may not support text completion. Choose another model in Configuration > Model. ASR draft below"
    }
    public var configReloaded: String { language == .chinese ? "配置已重新加载" : "Config reloaded" }
    public var configHotReloaded: String { language == .chinese ? "配置已自动更新" : "Config updated automatically" }
    public var modelsRefreshed: String { language == .chinese ? "模型列表已刷新" : "Models refreshed" }
    public var permissionIssue: String { language == .chinese ? "监听异常，请检查权限" : "Listening unavailable; check permissions" }
    public var eventTapWatchdogReset: String {
        language == .chinese ? "触发键状态已自动复位" : "Trigger state reset by watchdog"
    }
    public var inputMonitoringManual: String {
        MenuTooltipCatalog.inputMonitoringManual(language: language)
    }
    public var accessibilityManual: String {
        MenuTooltipCatalog.accessibilityManual(language: language)
    }
    public func permissionSummary(_ snapshot: PermissionSnapshot) -> String {
        if language == .chinese {
            return "权限：\(permissionValue(snapshot.microphoneGranted)) 麦克风 · \(permissionValue(snapshot.accessibilityGranted)) 辅助功能 · \(permissionValue(snapshot.inputMonitoringGranted)) 输入监控 · \(permissionValue(snapshot.speechRecognitionGranted)) 语音识别"
        }
        return "Permissions: \(permissionValue(snapshot.microphoneGranted)) Microphone · \(permissionValue(snapshot.accessibilityGranted)) Accessibility · \(permissionValue(snapshot.inputMonitoringGranted)) Input Monitoring · \(permissionValue(snapshot.speechRecognitionGranted)) Speech Recognition"
    }

    public func permissionValue(_ granted: Bool) -> String {
        granted ? "✓" : "×"
    }

    public func permissionDetail(_ label: String, granted: Bool) -> String {
        "\(permissionValue(granted)) \(label)"
    }

    public var permissionUsageTooltip: String {
        MenuTooltipCatalog.permissionUsage(language: language)
    }

    public func statusIdle(listeningEnabled: Bool, tapStatus: String) -> String {
        listeningEnabled ? tapStatus : (language == .chinese ? "监听已停止" : "Listening stopped")
    }

    public func statusRecording() -> String {
        language == .chinese ? "录音中" : "Recording"
    }

    public func statusTranscribing() -> String {
        language == .chinese ? "转写中" : "Transcribing"
    }

    public func listeningWithTrigger(_ trigger: TriggerKey) -> String {
        language == .chinese ? "监听中：\(triggerLabel(trigger))" : "Listening with \(triggerLabel(trigger))"
    }

    public func listeningUnavailable() -> String {
        language == .chinese ? "监听不可用；请检查输入监控权限" : "Listening unavailable; check Input Monitoring"
    }

    public func eventTapDisabled() -> String {
        language == .chinese ? "快捷键监听已停用" : "Shortcut listener disabled"
    }

    public func modelTitle(_ model: AllowedSpeechModel) -> String {
        language == .chinese ? "模型：\(model.rawValue)" : "Model: \(model.rawValue)"
    }

    public func pipelineModeTitle(_ mode: TranscriptionPipelineMode) -> String {
        language == .chinese
            ? "转写模式：\(mode.displayName(in: language))"
            : "Transcription Mode: \(mode.displayName(in: language))"
    }

    public func inputAudioModelTitle(_ model: AllowedSpeechModel) -> String {
        language == .chinese ? "音频模型：\(model.rawValue)" : "Input Audio Model: \(model.rawValue)"
    }

    public func textLLMModelTitle(_ model: AllowedSpeechModel) -> String {
        language == .chinese ? "文本模型：\(model.rawValue)" : "Text LLM Model: \(model.rawValue)"
    }

    public func systemASREngineTitle(_ engine: SystemASREngine) -> String {
        language == .chinese
            ? "识别引擎：\(engine.displayName(in: language))"
            : "Recognition Engine: \(engine.displayName(in: language))"
    }

    public func transcriptionSummaryTitle(
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

    public func modelConfigurationTitle(mode: TranscriptionPipelineMode, model: AllowedSpeechModel) -> String {
        if mode == .systemASROnly {
            return language == .chinese ? "模型：不使用大模型" : "Model: No LLM"
        }
        return language == .chinese
            ? "模型：\(mode.displayName(in: language)) · \(model.rawValue)"
            : "Model: \(mode.displayName(in: language)) · \(model.rawValue)"
    }

    public func apiSourceDoesNotExposeCurrentModel(_ model: AllowedSpeechModel) -> String {
        MenuTooltipCatalog.apiSourceDoesNotExposeCurrentModel(model, language: language)
    }

    public func systemASREngineTooltip(_ engine: SystemASREngine) -> String {
        MenuTooltipCatalog.systemASREngineTooltip(engine, language: language)
    }

    public func modelMenuItem(_ model: AllowedSpeechModel, observed: Bool?) -> String {
        guard observed == false else { return model.rawValue }
        return language == .chinese
            ? "\(model.rawValue)（未在 /v1/models 观测到）"
            : "\(model.rawValue) (not observed in /v1/models)"
    }

    public func uiLanguageTitle(_ uiLanguage: UILanguage) -> String {
        language == .chinese ? "语言：\(uiLanguage.displayName)" : "Language: \(uiLanguage.displayName)"
    }

    public func styleTitle(_ style: TranscriptionStyle) -> String {
        language == .chinese ? "风格：\(style.displayName(in: language))" : "Style: \(style.displayName(in: language))"
    }

    public func styleTitle(_ descriptor: TranscriptionStyleDescriptor) -> String {
        let name = styleMenuItem(descriptor)
        return language == .chinese ? "风格：\(name)" : "Style: \(name)"
    }

    public func styleMenuItem(_ descriptor: TranscriptionStyleDescriptor) -> String {
        let name = descriptor.localizedName(in: language)
        guard descriptor.isCustom else { return name }
        return language == .chinese ? "\(name)（自定义）" : "\(name) (Custom)"
    }

    public func keywordHintsTitle(enabled: Bool, selectedCount: Int) -> String {
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

    public func keywordGroupMenuItem(_ group: KeywordGroup) -> String {
        group.localizedName(in: language)
    }

    public func configHotReloadInvalidExported(_ path: String) -> String {
        language == .chinese
            ? "配置文件有问题，当前配置已导出到 \(path)"
            : "The config file has a problem; the current config was exported to \(path)"
    }

    public func panelStyleSwitchTitle(_ descriptor: TranscriptionStyleDescriptor) -> String {
        language == .chinese
            ? "风格：\(descriptor.localizedName(in: language))"
            : "Style: \(descriptor.localizedName(in: language))"
    }

    public func triggerTitle(_ trigger: TriggerKey) -> String {
        language == .chinese ? "触发键：\(triggerLabel(trigger))" : "Trigger: \(triggerLabel(trigger))"
    }

    public func recordingDurationTitle(min: MinRecordingDuration, max: MaxRecordingDuration) -> String {
        language == .chinese
            ? "录音时长：\(min.displayName)–\(max.displayName)"
            : "Duration: \(min.displayName)–\(max.displayName)"
    }

    public var minRecordingDuration: String {
        language == .chinese ? "最短录音" : "Minimum Recording"
    }

    public var maxRecordingDuration: String {
        language == .chinese ? "最长录音" : "Maximum Recording"
    }

    public func hudStyleTitle(_ style: HUDVisualStyle) -> String {
        language == .chinese ? "HUD 样式：\(style.displayName(in: language))" : "HUD Style: \(style.displayName(in: language))"
    }

    public func hudMessageDurationTitle(_ duration: HUDMessageDuration) -> String {
        language == .chinese ? "提示显示时长：\(duration.displayName)" : "Message Duration: \(duration.displayName)"
    }

    public func hudRevealDelayTitle(_ delay: HUDRevealDelay) -> String {
        language == .chinese
            ? "HUD 弹出延迟：\(delay.displayName(in: language))"
            : "HUD Reveal Delay: \(delay.displayName(in: language))"
    }

    public func liveASRPreviewTitle(enabled: Bool) -> String {
        language == .chinese
            ? "实时 ASR 预览：\(enabled ? "开" : "关")"
            : "Live ASR Preview: \(enabled ? "on" : "off")"
    }

    public var liveASRPreviewBadge: String {
        language == .chinese ? "草稿" : "Draft"
    }

    public func configurationTitle(_ config: MimoConfig) -> String {
        let status: String
        if config.apiKey?.nilIfBlank == nil {
            status = language == .chinese ? "缺少 API Key" : "Missing API Key"
        } else if !config.warnings.isEmpty {
            status = language == .chinese ? "需检查" : "Check needed"
        } else {
            status = language == .chinese ? "有效" : "Ready"
        }
        let source = config.activeSourceID
        return language == .chinese
            ? "配置：\(status) · \(source)"
            : "Configuration: \(status) · \(source)"
    }

    public func apiKeyStatus(_ config: MimoConfig) -> String {
        config.apiKey?.nilIfBlank == nil
            ? missing
            : config.redactedStatus.apiKeyPreview
    }

    public func configSource(_ config: MimoConfig) -> String {
        let label = config.activeSourceID == MimoConfig.autoSourceID
            ? (language == .chinese ? "自动 → \(config.resolvedSourceID)" : "auto → \(config.resolvedSourceID)")
            : config.activeSourceID
        return language == .chinese
            ? "来源：config 文件 · \(label)"
            : "Source: config file · \(label)"
    }

    public func configWarning(_ warning: String) -> String {
        switch warning {
        case "Config warning: config.jsonc containing secrets should be chmod 600":
            return language == .chinese
                ? "提醒：config.jsonc 包含 API Key，请保持文件权限为 0600"
                : "Reminder: config.jsonc contains an API key; keep file permissions at 0600"
        case "Config warning: config.jsonc could not be read":
            return language == .chinese
                ? "提醒：config.jsonc 无法读取，请检查文件格式"
                : "Reminder: config.jsonc could not be read; check the file format"
        case "Config warning: invalid Base URL, using default host":
            return language == .chinese
                ? "提醒：Base URL 无效，已临时使用默认地址"
                : "Reminder: Base URL is invalid; using the default address for now"
        case "Config file missing":
            return language == .chinese
                ? "提醒：config.jsonc 文件不存在"
                : "Reminder: config.jsonc is missing"
        case "Config warning: active source missing, using first source":
            return language == .chinese
                ? "提醒：当前来源不存在，已临时使用第一个来源"
                : "Reminder: selected source is missing; using the first source for now"
        case "Config warning: config.jsonc must use sources":
            return language == .chinese
                ? "提醒：config.jsonc 需要使用 sources 多来源格式"
                : "Reminder: config.jsonc must use the multi-source sources format"
        case "Config warning: config.jsonc needs at least one source":
            return language == .chinese
                ? "提醒：config.jsonc 至少需要一个 API 来源"
                : "Reminder: config.jsonc needs at least one API source"
        case "Config warning: invalid keyword groups ignored":
            return language == .chinese
                ? "提醒：部分关键词组无效，已忽略"
                : "Reminder: some keyword groups are invalid and were ignored"
        case "Config warning: invalid keywords ignored":
            return language == .chinese
                ? "提醒：部分关键词无效，已忽略"
                : "Reminder: some keywords are invalid and were ignored"
        case "Config warning: keyword group limit exceeded":
            return language == .chinese
                ? "提醒：单个关键词组最多使用 200 个关键词，超出部分已忽略"
                : "Reminder: each keyword group uses at most 200 keywords; extra items were ignored"
        case "Config warning: keyword hints exceed total limit":
            return language == .chinese
                ? "提醒：最多注入 500 个关键词，超出部分不会进入 prompt"
                : "Reminder: at most 500 keywords are injected; extra items are left out of the prompt"
        default:
            return warning
        }
    }

    public func apiSourceTitle(_ config: MimoConfig, mode: TranscriptionPipelineMode = .defaultMode) -> String {
        if mode == .systemASROnly {
            return language == .chinese ? "API 来源：仅系统 ASR" : "API Source: System ASR Only"
        }
        let label = config.activeSourceID == MimoConfig.autoSourceID
            ? (language == .chinese ? "自动" : "Auto")
            : config.activeSourceID
        return language == .chinese
            ? "API 来源：\(label)"
            : "API Source: \(label)"
    }

    public func autoAPISourceMenuItem(resolvedSourceID: String) -> String {
        language == .chinese
            ? "自动（选择最快可用来源） · 当前 \(resolvedSourceID)"
            : "Auto (fastest available source) · current \(resolvedSourceID)"
    }

    public func apiSourceMenuItem(_ source: ConfigSourceSummary, latency: SourceLatencyMeasurement?) -> String {
        let status = source.apiKeyConfigured ? configured : missing
        let latencyText: String
        if let latency, let milliseconds = latency.milliseconds {
            let modelText = latency.hasAllowedSpeechModel
                ? (language == .chinese ? "模型可用" : "models OK")
                : (language == .chinese ? "无可用模型" : "no speech model")
            latencyText = latency.reachable
                ? "\(milliseconds)ms · \(modelText)"
                : "\(milliseconds)ms · \(latency.httpStatus.map(String.init) ?? "failed")"
        } else if let latency {
            latencyText = latency.errorKind ?? (language == .chinese ? "失败" : "failed")
        } else {
            latencyText = language == .chinese ? "未测速" : "not measured"
        }
        return "\(source.id) · \(source.host) · \(status) · \(latencyText)"
    }

    public func latencyIntervalTitle(_ interval: ConfigLatencyInterval) -> String {
        language == .chinese
            ? "测速频率：\(latencyIntervalLabel(interval))"
            : "Latency Check: \(latencyIntervalLabel(interval))"
    }

    public func latencyIntervalLabel(_ interval: ConfigLatencyInterval) -> String {
        switch (language, interval) {
        case (.chinese, .off): return "关闭"
        case (.english, .off): return "Off"
        case (.chinese, .startupOnly): return "仅启动时"
        case (.english, .startupOnly): return "Startup only"
        case (.chinese, .seconds30): return "每 30 秒"
        case (.english, .seconds30): return "Every 30 seconds"
        case (.chinese, .minutes1): return "每 1 分钟"
        case (.english, .minutes1): return "Every 1 minute"
        case (.chinese, .minutes2): return "每 2 分钟"
        case (.english, .minutes2): return "Every 2 minutes"
        case (.chinese, .minutes5): return "每 5 分钟"
        case (.english, .minutes5): return "Every 5 minutes"
        case (.chinese, .minutes15): return "每 15 分钟"
        case (.english, .minutes15): return "Every 15 minutes"
        case (.chinese, .minutes30): return "每 30 分钟"
        case (.english, .minutes30): return "Every 30 minutes"
        case (.chinese, .minutes60): return "每 60 分钟"
        case (.english, .minutes60): return "Every 60 minutes"
        }
    }

    public func configSourceLabel(_ source: ConfigSource) -> String {
        switch language {
        case .chinese:
            switch source {
            case .configFile: return "config 文件"
            case .missing: return "未找到配置"
            }
        case .english:
            switch source {
            case .configFile: return "config file"
            case .missing: return "missing"
            }
        }
    }

    public func triggerLabel(_ trigger: TriggerKey) -> String {
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

    public func connectionCheckDefault() -> String {
        language == .chinese ? "检查连接与测速" : "Check Connection & Latency"
    }

    public func connectionCheckRunning() -> String {
        language == .chinese ? "检查连接与测速：运行中..." : "Check Connection & Latency: running..."
    }

    public func connectionCheckMessage(_ result: TestConnectionResult) -> String {
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

    public func transcriptionStyleTooltip(_ descriptor: TranscriptionStyleDescriptor) -> String {
        MenuTooltipCatalog.transcriptionStyleTooltip(descriptor, language: language)
    }

    public func tooltip(_ key: MenuTooltipKey) -> String {
        MenuTooltipCatalog.tooltip(key, language: language)
    }
}
