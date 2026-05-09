import Foundation

public enum MenuTooltipCatalog {
    private static let localizedTooltips: [MenuTooltipKey: [UILanguage: String]] = [
        .configuration: [
            .chinese: "打开配置入口，选择 API 来源、模型、系统识别和测速选项。",
            .english: "Open configuration actions for API source, models, system speech, and latency checks."
        ],
        .openConfigFile: [
            .chinese: "用代码编辑器打开 config.jsonc；找不到编辑器时使用系统默认应用。",
            .english: "Open config.jsonc in a code editor, or the system default app if no editor is found."
        ],
        .reloadConfig: [
            .chinese: "重新读取 config.jsonc，并应用其中的连接、模型和偏好设置。",
            .english: "Reload config.jsonc and apply its connection, model, and preference settings."
        ],
        .refreshModels: [
            .chinese: "从所有已配置 API 来源刷新模型列表；不会发送语音。",
            .english: "Refresh model lists from every configured API source. No voice audio is sent."
        ],
        .connectionCheck: [
            .chinese: "检查每个 API 来源是否可连接，并测量大致响应速度；不会发送语音。",
            .english: "Check every API source and measure rough response time. No voice audio is sent."
        ],
        .globalStop: [
            .chinese: "停止当前录音、识别、重试窗口和触发键监听。重新启用后可继续使用。",
            .english: "Stop recording, recognition, retry panels, and trigger listening. Re-enable to use OmniVoice again."
        ],
        .autoInsert: [
            .chinese: "开启后，转写完成会尝试写入当前可编辑输入框；不安全或不可写时仍会显示结果面板。",
            .english: "Insert final text into the focused editable field when safe; otherwise OmniVoice still shows the result panel."
        ],
        .launchAtLogin: [
            .chinese: "使用 macOS 登录项控制 OmniVoice 是否开机自动启动。",
            .english: "Use macOS Login Items to start OmniVoice automatically."
        ],
        .requestAllPermissions: [
            .chinese: """
            麦克风：点击后，在系统弹窗里选择允许。
            辅助功能和输入监控：macOS 可能只显示“去系统设置开启”的权限引导小对话框，并且它可能出现在其他 Space；若当前桌面没看到，请检查 Mission Control、其他 Space 或 Cmd+Tab。
            若列表中已有 OmniVoice 但仍无效，请移除后通过 + 重新添加 /Applications/OmniVoice.app。
            语音识别：点击后，在系统弹窗里选择允许；仅语音识别 + 文本转写或实时预览需要。
            """,
            .english: """
            Microphone: click, then choose Allow in the system prompt.
            Accessibility and Input Monitoring: macOS may show a small "open System Settings" permission guidance dialog, and it may appear in another Space. If it is not on the current desktop, check Mission Control, other Spaces, or Cmd+Tab.
            If OmniVoice is already listed but still missing permission, remove it and add /Applications/OmniVoice.app again.
            Speech Recognition: click, then choose Allow in the system prompt; only Speech Recognition + Text Rewrite or live preview needs it.
            """
        ],
        .requestMicrophone: [
            .chinese: "点击后，在系统弹窗里选择允许；麦克风用于录下你按住触发键时说的话。",
            .english: "Click, then choose Allow in the system prompt. The microphone records while you hold the trigger key."
        ],
        .requestAccessibility: [
            .chinese: "点击会请求 macOS 登记 OmniVoice，并打开系统设置的辅助功能页。macOS 可能不会显示允许/拒绝弹窗；“去系统设置开启”的权限引导小对话框可能出现在其他 Space。若当前桌面没看到，请检查 Mission Control、其他 Space 或 Cmd+Tab。若列表中已有但仍无效，请移除后通过 + 重新添加 /Applications/OmniVoice.app。",
            .english: "Click to ask macOS to register OmniVoice and open the Accessibility page in System Settings. macOS may not show an Allow/Deny prompt; the small permission guidance dialog can appear in another Space. If it is not on the current desktop, check Mission Control, other Spaces, or Cmd+Tab. If OmniVoice is listed but still not trusted, remove it and add /Applications/OmniVoice.app again."
        ],
        .requestInputMonitoring: [
            .chinese: "点击会请求 macOS 登记 OmniVoice，并打开系统设置的输入监控页。macOS 可能不会显示允许/拒绝弹窗；“去系统设置开启”的权限引导小对话框可能出现在其他 Space。若当前桌面没看到，请检查 Mission Control、其他 Space 或 Cmd+Tab。若列表中已有但仍无效，请移除后通过 + 重新添加 /Applications/OmniVoice.app。",
            .english: "Click to ask macOS to register OmniVoice and open the Input Monitoring page in System Settings. macOS may not show an Allow/Deny prompt; the small permission guidance dialog can appear in another Space. If it is not on the current desktop, check Mission Control, other Spaces, or Cmd+Tab. If OmniVoice is listed but still missing permission, remove it and add /Applications/OmniVoice.app again."
        ],
        .requestSpeechRecognition: [
            .chinese: "点击后，在系统弹窗里选择允许。只有使用语音识别 + 文本转写或实时 ASR 预览时才需要。",
            .english: "Click, then choose Allow in the system prompt. Only Speech Recognition + Text Rewrite or Live ASR Preview needs it."
        ],
        .transcriptionMode: [
            .chinese: "选择直接把音频交给多模态模型，或先用 macOS 识别再交给文本模型修正。",
            .english: "Choose direct omnimodal audio transcription or macOS Speech followed by text-model cleanup."
        ],
        .inputAudioModel: [
            .chinese: "用于音频直转模式的模型。菜单只列出配置池中已被模型列表观测到的模型。",
            .english: "Model used for Direct Audio mode. The menu only lists configured candidates observed from model lists."
        ],
        .textLLMModel: [
            .chinese: "用于修正系统识别草稿、重写和应用风格的文本模型。候选来自模型列表接口，若模型不支持文本补全，请更换模型。",
            .english: "Text model used to correct system speech drafts, rewrite, and apply styles. Candidates come from the models endpoint; choose another model if one does not support text completion."
        ],
        .editModelList: [
            .chinese: "打开 config.jsonc。Audio LLM 候选在这里维护；Text LLM 只配置默认模型，候选来自模型列表接口。",
            .english: "Open config.jsonc. Maintain Audio LLM candidates here; Text LLM only stores the default model and lists candidates from the models endpoint."
        ],
        .modelNotObserved: [
            .chinese: "音频模型按配置池过滤；文本模型来自当前 API 来源观测到的模型列表。",
            .english: "Audio models are filtered by the configured pool; text models come from API source model lists."
        ],
        .systemASR: [
            .chinese: "配置 macOS 系统语音识别和显式 Apple 在线识别。",
            .english: "Configure macOS Speech recognition and explicit Apple online recognition."
        ],
        .systemASREngine: [
            .chinese: "选择系统语音识别引擎；Apple 在线识别只会在显式选择后使用。",
            .english: "Choose the system speech engine. Apple online recognition is used only when explicitly selected."
        ],
        .systemASRKeywordHints: [
            .chinese: "把启用的关键词组交给系统语音识别，提高专有名词、产品名和技术词准确率。",
            .english: "Send enabled keyword groups to system speech recognition for names, product terms, and technical words."
        ],
        .triggerCapture: [
            .chinese: "只接受 Fn/Globe、F1-F12、左右修饰键和 Caps Lock。Esc 取消。",
            .english: "Only Fn/Globe, F1-F12, left/right modifiers, and Caps Lock are accepted. Esc cancels."
        ],
        .continuousRecordingDoubleTap: [
            .chinese: "开启后，短按触发键两次会保持录音；再次单击触发键停止。按住录音的原有方式不变。Caps Lock 暂不支持。",
            .english: "When enabled, two quick trigger taps keep recording until the next tap. Press-and-hold recording is unchanged. Caps Lock is not supported yet."
        ],
        .styleConcise: [
            .chinese: "整理成适合直接发送或输入的文字：去掉口头停顿，补上自然标点，不改变你的意思。",
            .english: "Clean up pauses and repeated starts, add natural punctuation, and keep your meaning."
        ],
        .styleVerbatim: [
            .chinese: "尽量保留你的原话，只做必要的识别纠错和标点补全。",
            .english: "Keep your wording as much as possible, with only basic recognition fixes and punctuation."
        ],
        .styleTechnical: [
            .chinese: "适合技术内容：尽量保留命令、路径、代码标识符、大小写、符号和英文词。",
            .english: "Best for technical content; preserves commands, paths, identifiers, casing, symbols, and English terms."
        ],
        .styleRewrite: [
            .chinese: "把口述整理成更清晰、自然、可发送的文字，但不新增事实或承诺。",
            .english: "Rewrite speech into clearer, more sendable text without adding facts or promises."
        ],
        .customStyles: [
            .chinese: "打开 config.jsonc 后，可以用 custom_styles 添加自己的转写风格。",
            .english: "Open config.jsonc to add your own transcription styles with custom_styles."
        ],
        .keywordHints: [
            .chinese: "把选中的关键词组作为识别提示加入转写；只在发音和上下文合理时参考。",
            .english: "Add selected keyword groups as recognition hints when the audio and context fit."
        ],
        .displayHints: [
            .chinese: "调整 HUD 样式、实时草稿预览、短提示停留时间和 HUD 出现速度。",
            .english: "Adjust HUD style, live draft preview, short-message duration, and how quickly the listening HUD appears."
        ],
        .liveASRPreview: [
            .chinese: "录音时用系统语音识别在 HUD 中显示实时文本。它只是预览，最终文本仍由当前转写模式生成。",
            .english: "Show live system speech text in the HUD while recording. It is preview-only; final text still comes from the selected transcription mode."
        ],
        .hudMessageDuration: [
            .chinese: "设置短提示自动消失前停留多久。",
            .english: "Choose how long short status messages stay visible."
        ],
        .hudRevealDelay: [
            .chinese: "录音会在按下触发键时立即开始；这里只控制聆听 HUD 延迟多久出现。",
            .english: "Recording starts as soon as the trigger is pressed; this only controls how long the listening HUD waits before appearing."
        ],
        .latency: [
            .chinese: "用模型列表接口测量每个 API 来源的大致响应速度，不发送音频。",
            .english: "Measure each API source with the models endpoint. No audio is sent."
        ],
        .apiSourceAuto: [
            .chinese: "自动选择最近一次测速中可连接、包含当前模型、响应最快的 API 来源。",
            .english: "Automatically choose the fastest reachable API source that includes the current model."
        ],
        .apiSourceAvailable: [
            .chinese: "切换到这个 API 来源；它的模型列表包含当前选择的模型。",
            .english: "Switch to this API source. Its model list includes the currently selected model."
        ],
        .systemASROnlyMode: [
            .chinese: "只使用当前系统语音识别引擎生成文字，不调用模型 API。",
            .english: "Use the current system speech recognition engine only. No model API is called."
        ]
    ]

    public static func tooltip(_ key: MenuTooltipKey, language: UILanguage) -> String {
        localizedTooltips[key]?[language] ?? ""
    }

    public static func permissionUsage(language: UILanguage) -> String {
        switch language {
        case .chinese:
            return """
            麦克风：按住触发键时录下你的声音。
            辅助功能：确认当前输入框是否可以写入，并在可行时放入文字。
            输入监控：识别你按下和松开触发键的动作。
            语音识别：使用语音识别 + 文本转写或实时预览时，把语音转成草稿。
            """
        case .english:
            return """
            Microphone: records your voice while you hold the trigger key.
            Accessibility: checks whether the current text field can receive text and inserts it when possible.
            Input Monitoring: notices when you press and release the trigger key.
            Speech Recognition: turns speech into a draft for Speech Recognition + Text Rewrite or live preview.
            """
        }
    }

    public static func accessibilityManual(language: UILanguage) -> String {
        switch language {
        case .chinese:
            return "请去系统设置 > 隐私与安全性 > 辅助功能，开启 OmniVoice。若“去系统设置开启”的权限引导小对话框不在当前桌面，请检查其他 Space、Mission Control 或 Cmd+Tab。"
        case .english:
            return "Go to System Settings > Privacy & Security > Accessibility and turn on OmniVoice. If the small permission guidance dialog is not on the current desktop, check other Spaces, Mission Control, or Cmd+Tab."
        }
    }

    public static func inputMonitoringManual(language: UILanguage) -> String {
        switch language {
        case .chinese:
            return "请去系统设置 > 隐私与安全性 > 输入监控，开启 OmniVoice。若“去系统设置开启”的权限引导小对话框不在当前桌面，请检查其他 Space、Mission Control 或 Cmd+Tab。"
        case .english:
            return "Go to System Settings > Privacy & Security > Input Monitoring and turn on OmniVoice. If the small permission guidance dialog is not on the current desktop, check other Spaces, Mission Control, or Cmd+Tab."
        }
    }

    public static func apiSourceDoesNotExposeCurrentModel(_ model: AllowedSpeechModel, language: UILanguage) -> String {
        switch language {
        case .chinese:
            return "当前模型 \(model.rawValue) 不在这个来源的模型列表中。"
        case .english:
            return "The current model \(model.rawValue) is not in this source's model list."
        }
    }

    public static func systemASREngineTooltip(_ engine: SystemASREngine, language: UILanguage) -> String {
        switch (language, engine) {
        case (.chinese, .speechAnalyzer):
            return "macOS 26+ 默认端侧识别引擎。启动前会检查语言、语音资源和音频格式；低版本系统不可用。"
        case (.english, .speechAnalyzer):
            return "Default on-device engine on macOS 26 or later. OmniVoice checks language support, speech resources, and audio format before starting; unavailable on older systems."
        case (.chinese, .classicSpeech):
            return "端侧经典 Speech。音频不主动发送给 Apple 在线服务；如果当前语言不支持端侧识别，会提示切换引擎。"
        case (.english, .classicSpeech):
            return "Classic on-device Speech. Audio is not intentionally sent to Apple online services; switch engines if on-device recognition is unavailable for the current language."
        case (.chinese, .appleOnlineSpeech):
            return "通过 macOS 可免费使用，但可能把音频发送给 Apple，并受服务可用性、每日限制和约一分钟任务限制影响。"
        case (.english, .appleOnlineSpeech):
            return "Free through macOS, but may send audio to Apple and can be limited by service availability, daily limits, and roughly one-minute tasks."
        }
    }

    public static func transcriptionStyleTooltip(
        _ descriptor: TranscriptionStyleDescriptor,
        language: UILanguage
    ) -> String {
        if let customTooltip = descriptor.localizedTooltip(in: language) {
            return customTooltip
        }
        switch descriptor.builtInStyle {
        case .concise:
            return tooltip(.styleConcise, language: language)
        case .verbatim:
            return tooltip(.styleVerbatim, language: language)
        case .codeFaithful:
            return tooltip(.styleTechnical, language: language)
        case .rewrite:
            return tooltip(.styleRewrite, language: language)
        case nil:
            return tooltip(.customStyles, language: language)
        }
    }
}

public enum MenuTooltipKey: CaseIterable, Sendable {
    case configuration
    case openConfigFile
    case reloadConfig
    case refreshModels
    case connectionCheck
    case globalStop
    case autoInsert
    case launchAtLogin
    case requestMicrophone
    case requestAccessibility
    case requestInputMonitoring
    case requestSpeechRecognition
    case requestAllPermissions
    case transcriptionMode
    case inputAudioModel
    case textLLMModel
    case editModelList
    case modelNotObserved
    case systemASR
    case systemASREngine
    case systemASRKeywordHints
    case triggerCapture
    case continuousRecordingDoubleTap
    case styleConcise
    case styleVerbatim
    case styleTechnical
    case styleRewrite
    case customStyles
    case keywordHints
    case displayHints
    case liveASRPreview
    case hudMessageDuration
    case hudRevealDelay
    case latency
    case apiSourceAuto
    case apiSourceAvailable
    case systemASROnlyMode
}
