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
    public var configured: String { language == .chinese ? "已配置" : "configured" }
    public var missing: String { language == .chinese ? "缺失" : "missing" }
    public var autoInsert: String { language == .chinese ? "自动插入" : "Auto Insert" }
    public var reloadConfig: String { language == .chinese ? "重新加载配置" : "Reload Config" }
    public var refreshModels: String { language == .chinese ? "刷新模型" : "Refresh Models" }
    public var permissions: String { language == .chinese ? "权限" : "Permissions" }
    public var configuration: String { language == .chinese ? "配置" : "Configuration" }
    public var apiSource: String { language == .chinese ? "API 来源" : "API Source" }
    public var latencyInterval: String { language == .chinese ? "测速频率" : "Latency Check" }
    public var connectionLatencyCompleted: String { language == .chinese ? "连接检查与测速已完成" : "Connection and latency check complete" }
    public var editCustomStyles: String { language == .chinese ? "打开 config.jsonc 编辑自定义风格" : "Open config.jsonc to edit custom styles" }
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
    public var hudStyle: String { language == .chinese ? "HUD 样式" : "HUD Style" }
    public var hudMessageDuration: String { language == .chinese ? "提示显示时长" : "Message Duration" }
    public var retry: String { language == .chinese ? "重试" : "Retry" }
    public var requestFailed: String { language == .chinese ? "请求失败" : "Request Failed" }
    public var recordTriggerKey: String { language == .chinese ? "录制触发键" : "Record Trigger Key" }
    public var recordingTriggerKey: String { language == .chinese ? "请按一个可用触发键" : "Press an allowed trigger key" }
    public var triggerRecordingHelp: String {
        language == .chinese
            ? "只接受 Fn/Globe、F1-F12、左右修饰键和 Caps Lock。Esc 取消。"
            : "Only Fn/Globe, F1-F12, left/right modifiers, and Caps Lock are accepted. Esc cancels."
    }
    public var triggerRecordingRejected: String {
        language == .chinese ? "这个按键不能作为触发键" : "This key cannot be used as a trigger"
    }
    public var restart: String { language == .chinese ? "重启 OmniVoice" : "Restart OmniVoice" }
    public var quit: String { language == .chinese ? "退出 OmniVoice" : "Quit OmniVoice" }
    public var restartFailed: String { language == .chinese ? "重启失败" : "Restart failed" }
    public var requestAllPermissions: String { language == .chinese ? "请求所有权限" : "Request All Permissions" }
    public var requestMicrophone: String { language == .chinese ? "请求麦克风权限" : "Request Microphone Permission" }
    public var requestAccessibility: String { language == .chinese ? "请求辅助功能权限" : "Request Accessibility Permission" }
    public var requestInputMonitoring: String { language == .chinese ? "请求输入监控权限" : "Request Input Monitoring Permission" }
    public var permissionManagement: String { language == .chinese ? "权限管理" : "Permission Management" }
    public var openMicrophoneSettings: String { language == .chinese ? "打开麦克风设置" : "Open Microphone Settings" }
    public var openAccessibilitySettings: String { language == .chinese ? "打开辅助功能设置" : "Open Accessibility Settings" }
    public var openInputMonitoringSettings: String { language == .chinese ? "打开输入监控设置" : "Open Input Monitoring Settings" }
    public var copy: String { language == .chinese ? "复制" : "Copy" }
    public var cancel: String { language == .chinese ? "取消" : "Cancel" }
    public var copied: String { language == .chinese ? "已复制" : "Copied" }
    public var listening: String { language == .chinese ? "正在聆听" : "Listening" }
    public var transcribing: String { language == .chinese ? "正在转写" : "Transcribing" }
    public var cancelled: String { language == .chinese ? "已取消" : "Cancelled" }
    public var noTextRecognized: String { language == .chinese ? "没有识别到文本" : "No text recognized" }
    public var configReloaded: String { language == .chinese ? "配置已重新加载" : "Config reloaded" }
    public var modelsRefreshed: String { language == .chinese ? "模型列表已刷新" : "Models refreshed" }
    public var permissionIssue: String { language == .chinese ? "监听异常，请检查权限" : "Listening unavailable; check permissions" }
    public var eventTapWatchdogReset: String {
        language == .chinese ? "触发键状态已自动复位" : "Trigger state reset by watchdog"
    }
    public var inputMonitoringManual: String {
        language == .chinese ? "输入监控需要在系统设置中手动开启" : "Enable Input Monitoring manually in System Settings"
    }
    public func permissionSummary(_ snapshot: PermissionSnapshot) -> String {
        if language == .chinese {
            return "权限：\(permissionValue(snapshot.microphoneGranted)) 麦克风 · \(permissionValue(snapshot.accessibilityGranted)) 辅助功能 · \(permissionValue(snapshot.inputMonitoringGranted)) 输入监控"
        }
        return "Permissions: \(permissionValue(snapshot.microphoneGranted)) Microphone · \(permissionValue(snapshot.accessibilityGranted)) Accessibility · \(permissionValue(snapshot.inputMonitoringGranted)) Input Monitoring"
    }

    public func permissionValue(_ granted: Bool) -> String {
        granted ? "✓" : "×"
    }

    public func permissionDetail(_ label: String, granted: Bool) -> String {
        "\(permissionValue(granted)) \(label)"
    }

    public var permissionUsageTooltip: String {
        switch language {
        case .chinese:
            return """
            麦克风：按住触发键时录下你的声音。
            辅助功能：确认当前输入框是否可以写入，并在可行时放入文字。
            输入监控：识别你按下和松开触发键的动作。
            """
        case .english:
            return """
            Microphone: records your voice while you hold the trigger key.
            Accessibility: checks whether the current text field can receive text and inserts it when possible.
            Input Monitoring: notices when you press and release the trigger key.
            """
        }
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
        default:
            return warning
        }
    }

    public func apiSourceTitle(_ config: MimoConfig) -> String {
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
        return language == .chinese
            ? "连接可用；\(result.selectedModel) 可以使用"
            : "Connection OK; \(result.selectedModel) is available"
    }

    public func tooltip(_ key: MenuTooltipKey) -> String {
        switch (language, key) {
        case (.chinese, .configuration):
            return "打开 config 文件，选择 API 来源，并检查连接状态。"
        case (.english, .configuration):
            return "Open the config file, choose an API source, and check connection status."
        case (.chinese, .reloadConfig):
            return "重新读取 config 文件里的连接信息。"
        case (.english, .reloadConfig):
            return "Reload connection details from the config file."
        case (.chinese, .refreshModels):
            return "重新获取可用于语音识别的模型列表。"
        case (.english, .refreshModels):
            return "Refresh the list of speech transcription models."
        case (.chinese, .connectionCheck):
            return "检查每个 API 来源是否可连接，并测量大致响应速度；不会发送语音。"
        case (.english, .connectionCheck):
            return "Check every API source and measure rough response time. No voice audio is sent."
        case (.chinese, .globalStop):
            return "停止当前录音、识别、重试窗口和快捷键监听。重新启用后可继续使用。"
        case (.english, .globalStop):
            return "Stop recording, recognition, retry panels, and trigger listening. Re-enable to use OmniVoice again."
        case (.chinese, .autoInsert):
            return "开启后转写完成会尝试写入当前可编辑输入框。"
        case (.english, .autoInsert):
            return "Paste final text into the focused editable field when possible."
        case (.chinese, .launchAtLogin):
            return "使用 macOS 登录项控制 OmniVoice 是否开机自动启动。"
        case (.english, .launchAtLogin):
            return "Use macOS Login Items to start OmniVoice automatically."
        case (.chinese, .requestAllPermissions):
            return """
            麦克风：点击后，在系统弹窗里选择允许。
            辅助功能：会打开系统设置；如果列表里已有 OmniVoice 但仍无效，请先移除，再重新添加 /Applications/OmniVoice.app。
            输入监控：会打开系统设置；如果列表里已有 OmniVoice 但仍无效，请先移除，再重新添加 /Applications/OmniVoice.app。
            """
        case (.english, .requestAllPermissions):
            return """
            Microphone: click, then choose Allow in the system prompt.
            Accessibility: opens System Settings. If OmniVoice is already listed but still missing, remove it and add /Applications/OmniVoice.app again.
            Input Monitoring: opens System Settings. If OmniVoice is already listed but still missing, remove it and add /Applications/OmniVoice.app again.
            """
        case (.chinese, .requestInputMonitoring):
            return "如果列表中已有 OmniVoice 但仍无权限，请先移除，再点 + 重新选择 /Applications/OmniVoice.app。"
        case (.english, .requestInputMonitoring):
            return "If OmniVoice is already listed but still missing permission, remove it, then add /Applications/OmniVoice.app again."
        case (.chinese, .requestAccessibility):
            return "如果列表中已有 OmniVoice 且已开启但仍无权限，请移除后通过 + 重新添加 /Applications/OmniVoice.app。"
        case (.english, .requestAccessibility):
            return "If OmniVoice is enabled but still not trusted, remove it and add /Applications/OmniVoice.app again."
        case (.chinese, .requestMicrophone):
            return "点击后，在系统弹窗里选择允许。"
        case (.english, .requestMicrophone):
            return "Click, then choose Allow in the system prompt."
        case (.chinese, .apiSourceAuto):
            return "自动选择最近一次测速中可连接、包含可用语音模型、响应最快的 API 来源。"
        case (.english, .apiSourceAuto):
            return "Automatically choose the fastest reachable API source that includes a usable speech model."
        case (.chinese, .triggerCapture):
            return triggerRecordingHelp
        case (.english, .triggerCapture):
            return triggerRecordingHelp
        case (.chinese, .styleConcise):
            return "整理成适合直接发送或输入的文字：去掉口头停顿，补上自然标点，不改变你的意思。"
        case (.english, .styleConcise):
            return "Clean up pauses and repeated starts, add natural punctuation, and keep your meaning."
        case (.chinese, .styleVerbatim):
            return "尽量保留你的原话，只做必要的识别纠错和标点补全。"
        case (.english, .styleVerbatim):
            return "Keep your wording as much as possible, with only basic recognition fixes and punctuation."
        case (.chinese, .styleTechnical):
            return "适合技术内容：尽量保留命令、路径、代码标识符、大小写、符号和英文词。"
        case (.english, .styleTechnical):
            return "Best for technical content; preserves commands, paths, identifiers, casing, symbols, and English terms."
        case (.chinese, .styleRewrite):
            return "把口述整理成更清晰、自然、可发送的文字，但不新增事实或承诺。"
        case (.english, .styleRewrite):
            return "Rewrite speech into clearer, more sendable text without adding facts or promises."
        case (.chinese, .customStyles):
            return "打开配置文件后，可以用 custom_styles 添加自己的转写风格。"
        case (.english, .customStyles):
            return "Open the config file to add your own transcription styles with custom_styles."
        case (.chinese, .hudMessageDuration):
            return "设置短提示自动消失前停留多久。"
        case (.english, .hudMessageDuration):
            return "Choose how long short status messages stay visible."
        case (.chinese, .latency):
            return "用模型列表接口测量每个 API 来源的大致响应速度，不发送音频。"
        case (.english, .latency):
            return "Measure each API source with the models endpoint. No audio is sent."
        }
    }
}

public enum MenuTooltipKey: Sendable {
    case configuration
    case reloadConfig
    case refreshModels
    case connectionCheck
    case globalStop
    case autoInsert
    case launchAtLogin
    case requestMicrophone
    case requestAccessibility
    case requestInputMonitoring
    case requestAllPermissions
    case triggerCapture
    case styleConcise
    case styleVerbatim
    case styleTechnical
    case styleRewrite
    case customStyles
    case hudMessageDuration
    case latency
    case apiSourceAuto
}
