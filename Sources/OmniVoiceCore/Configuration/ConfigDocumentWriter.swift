import Foundation

public enum ConfigDocumentWriter {
    public static func defaultDocument(uiLanguage: UILanguage) -> String {
        document(config: defaultConfig(uiLanguage: uiLanguage), uiLanguage: uiLanguage)
    }

    public static func document(config: MimoConfig, uiLanguage: UILanguage) -> String {
        let text = ConfigDocumentText(language: uiLanguage)
        var lines: [String] = ["{"]

        addComment(text.fileIntro, indent: 2, to: &lines)
        addComment(text.activeSource, indent: 2, to: &lines)
        lines.append("  \"active_source\": \(jsonString(config.activeSourceID)),")
        addComment(text.transcriptionPipeline, indent: 2, to: &lines)
        lines.append("  \"transcription_pipeline\": {")
        addComment(text.transcriptionPipelineMode, indent: 4, to: &lines)
        lines.append("    \"mode\": \(jsonString(config.pipelineMode.rawValue))")
        lines.append("  },")
        addComment(text.models, indent: 2, to: &lines)
        lines.append("  \"models\": {")
        lines.append("    \"audio_llm\": {")
        addComment(text.inputAudioDefaultModel, indent: 6, to: &lines)
        lines.append("      \"default_model\": \(jsonString(config.modelCatalogs.inputAudioDefaultModel.rawValue)),")
        addComment(text.inputAudioExtraModels, indent: 6, to: &lines)
        appendJSONStringArrayProperty(
            name: "extra_models",
            values: config.modelCatalogs.inputAudioExtraModels.map(\.rawValue),
            indent: 6,
            trailingComma: false,
            to: &lines
        )
        lines.append("    },")
        lines.append("    \"text_llm\": {")
        addComment(text.textLLMDefaultModel, indent: 6, to: &lines)
        lines.append("      \"default_model\": \(jsonString(config.modelCatalogs.textLLMDefaultModel.rawValue))")
        lines.append("    }")
        lines.append("  },")
        addComment(text.systemASR, indent: 2, to: &lines)
        lines.append("  \"system_asr\": {")
        addComment(text.systemASREngine, indent: 4, to: &lines)
        lines.append("    \"engine\": \(jsonString(config.systemASRSettings.engine.rawValue)),")
        addComment(text.systemASRKeywordHints, indent: 4, to: &lines)
        lines.append("    \"keyword_hints_enabled\": \(config.systemASRSettings.keywordHintsEnabled ? "true" : "false")")
        lines.append("  },")
        addComment(text.sources, indent: 2, to: &lines)
        lines.append("  \"sources\": {")
        let sources = config.sources.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        for (index, source) in sources.enumerated() {
            addComment(text.source(source.id), indent: 4, to: &lines)
            lines.append("    \(jsonString(source.id)): {")
            addComment(text.baseURL, indent: 6, to: &lines)
            lines.append("      \"base_url\": \(jsonString(source.baseURL.absoluteString)),")
            addComment(text.apiKey, indent: 6, to: &lines)
            lines.append("      \"api_key\": \(jsonString(source.apiKey ?? ""))")
            lines.append("    }\(index == sources.count - 1 ? "" : ",")")
        }
        lines.append("  },")

        addComment(text.latency, indent: 2, to: &lines)
        lines.append("  \"latency\": {")
        addComment(text.latencyEnabled, indent: 4, to: &lines)
        lines.append("    \"enabled\": \(config.latencySettings.interval == .off ? "false" : "true"),")
        addComment(text.latencyInterval, indent: 4, to: &lines)
        if let seconds = config.latencySettings.interval.seconds {
            lines.append("    \"interval_seconds\": \(seconds)")
        } else {
            lines.append("    \"interval_seconds\": null")
        }
        lines.append("  },")

        let preferences = config.preferences.with(selectedModel: config.modelCatalogs.inputAudioDefaultModel, uiLanguage: uiLanguage)
        addComment(text.preferences, indent: 2, to: &lines)
        lines.append("  \"preferences\": {")
        addComment(text.uiLanguage, indent: 4, to: &lines)
        lines.append("    \"ui_language\": \(jsonString(preferences.uiLanguage.rawValue)),")
        addComment(text.transcriptionStyle, indent: 4, to: &lines)
        lines.append("    \"transcription_style\": \(jsonString(preferences.transcriptionStyleSelection.rawValue)),")
        addComment(text.keywordHintsEnabled, indent: 4, to: &lines)
        lines.append("    \"keyword_hints_enabled\": \(preferences.keywordHintsEnabled ? "true" : "false"),")
        addComment(text.enabledKeywordGroups, indent: 4, to: &lines)
        appendJSONStringArrayProperty(
            name: "enabled_keyword_groups",
            values: preferences.enabledKeywordGroupIDs,
            indent: 4,
            trailingComma: true,
            to: &lines
        )
        addComment(text.triggerKey, indent: 4, to: &lines)
        lines.append("    \"trigger_key\": \(jsonString(preferences.triggerKey.identifier)),")
        addComment(text.continuousRecordingDoubleTap, indent: 4, to: &lines)
        lines.append("    \"trigger\": {")
        lines.append("      \"continuous_recording_double_tap_enabled\": \(preferences.continuousRecordingDoubleTapEnabled ? "true" : "false")")
        lines.append("    },")
        addComment(text.minRecording, indent: 4, to: &lines)
        lines.append("    \"min_recording_duration_ms\": \(preferences.minRecordingDuration.rawValue),")
        addComment(text.maxRecording, indent: 4, to: &lines)
        lines.append("    \"max_recording_duration_seconds\": \(preferences.maxRecordingDuration.rawValue),")
        addComment(text.autoInsert, indent: 4, to: &lines)
        lines.append("    \"auto_insert\": \(preferences.autoInsert ? "true" : "false"),")
        addComment(text.launchAtLogin, indent: 4, to: &lines)
        lines.append("    \"launch_at_login\": \(preferences.launchAtLogin ? "true" : "false"),")
        addComment(text.hud, indent: 4, to: &lines)
        lines.append("    \"hud\": {")
        addComment(text.hudVisualStyle, indent: 6, to: &lines)
        lines.append("      \"visual_style\": \(jsonString(preferences.hudVisualStyle.rawValue)),")
        addComment(text.hudMessageDuration, indent: 6, to: &lines)
        lines.append("      \"message_duration_seconds\": \(preferences.hudMessageDuration.rawValue),")
        addComment(text.hudRevealDelay, indent: 6, to: &lines)
        lines.append("      \"reveal_delay_ms\": \(preferences.hudRevealDelay.rawValue),")
        addComment(text.liveASRPreview, indent: 6, to: &lines)
        lines.append("      \"live_asr_preview_enabled\": \(preferences.liveASRPreviewEnabled ? "true" : "false")")
        lines.append("    }")
        lines.append("  },")

        addComment(text.customStyles, indent: 2, to: &lines)
        lines.append("  \"custom_styles\": {")
        let styles = config.customStyles.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        for (index, style) in styles.enumerated() {
            addComment(text.customStyle(style.id), indent: 4, to: &lines)
            lines.append("    \(jsonString(style.id)): {")
            addComment(text.customDisplayName, indent: 6, to: &lines)
            lines.append("      \"display_name\": \(jsonString(style.displayName)),")
            addComment(text.customPromptLines, indent: 6, to: &lines)
            let promptLines = style.prompt.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            appendJSONStringArrayProperty(
                name: "prompt_lines",
                values: promptLines,
                indent: 6,
                trailingComma: false,
                to: &lines
            )
            lines.append("    }\(index == styles.count - 1 ? "" : ",")")
        }
        lines.append("  },")

        addComment(text.keywordGroups, indent: 2, to: &lines)
        lines.append("  \"keyword_groups\": {")
        let keywordGroups = config.keywordGroups.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        for (index, group) in keywordGroups.enumerated() {
            addComment(text.keywordGroup(group.id), indent: 4, to: &lines)
            lines.append("    \(jsonString(group.id)): {")
            addComment(text.keywordDisplayName, indent: 6, to: &lines)
            lines.append("      \"display_name\": \(jsonString(group.displayName ?? group.id)),")
            addComment(text.keywords, indent: 6, to: &lines)
            appendJSONStringArrayProperty(
                name: "keywords",
                values: group.keywords,
                indent: 6,
                trailingComma: false,
                to: &lines
            )
            lines.append("    }\(index == keywordGroups.count - 1 ? "" : ",")")
        }
        lines.append("  }")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func defaultConfig(uiLanguage: UILanguage) -> MimoConfig {
        let cnSource = MimoConfigSource(
            id: "cn",
            baseURL: MimoConfig.defaultBaseURL,
            apiKey: ""
        )
        let sgpSource = MimoConfigSource(
            id: "sgp",
            baseURL: URL(string: "https://token-plan-sgp.xiaomimimo.com")!,
            apiKey: ""
        )
        return MimoConfig(
            baseURL: cnSource.baseURL,
            apiKey: nil,
            defaultModel: .defaultModel,
            source: .configFile,
            activeSourceID: cnSource.id,
            resolvedSourceID: cnSource.id,
            sources: [cnSource, sgpSource],
            modelCatalogs: .defaultCatalogs,
            pipelineMode: .defaultMode,
            systemASRSettings: .defaultSettings,
            customStyles: [defaultCustomStyle(uiLanguage: uiLanguage)],
            keywordGroups: defaultKeywordGroups(uiLanguage: uiLanguage),
            latencySettings: .defaultSettings,
            preferences: .defaultPreferences(selectedModel: .defaultModel, uiLanguage: uiLanguage)
        )
    }

    private static func defaultKeywordGroups(uiLanguage: UILanguage) -> [KeywordGroup] {
        switch uiLanguage {
        case .chinese:
            return [
                KeywordGroup(
                    id: "mimo_e2e_terms",
                    displayName: "MiMo E2E Terms",
                    keywords: ["OmniVoice", "MiMo", "mimo-v2.5", "mimo-v2-omni", "mimo-v2-pro", "mimo-v2.5-pro", "config.jsonc", "Swift", "API"]
                ),
                KeywordGroup(
                    id: "omnivoice_terms",
                    displayName: "OmniVoice 术语",
                    keywords: ["OmniVoice", "MiMo", "mimo-v2.5", "mimo-v2-omni", "mimo-v2-pro", "mimo-v2.5-pro", "config.jsonc", "ActionPanel", "HUD", "Panel"]
                ),
                KeywordGroup(
                    id: "technical_terms",
                    displayName: "技术术语",
                    keywords: ["Swift", "AppKit", "macOS", "JSONC", "API", "make run", "Cmd+V", "Fn"]
                )
            ]
        case .english:
            return [
                KeywordGroup(
                    id: "mimo_e2e_terms",
                    displayName: "MiMo E2E Terms",
                    keywords: ["OmniVoice", "MiMo", "mimo-v2.5", "mimo-v2-omni", "mimo-v2-pro", "mimo-v2.5-pro", "config.jsonc", "Swift", "API"]
                ),
                KeywordGroup(
                    id: "omnivoice_terms",
                    displayName: "OmniVoice Terms",
                    keywords: ["OmniVoice", "MiMo", "mimo-v2.5", "mimo-v2-omni", "mimo-v2-pro", "mimo-v2.5-pro", "config.jsonc", "ActionPanel", "HUD", "Panel"]
                ),
                KeywordGroup(
                    id: "technical_terms",
                    displayName: "Technical Terms",
                    keywords: ["Swift", "AppKit", "macOS", "JSONC", "API", "make run", "Cmd+V", "Fn"]
                )
            ]
        }
    }

    private static func defaultCustomStyle(uiLanguage: UILanguage) -> CustomTranscriptionStyle {
        switch uiLanguage {
        case .chinese:
            return CustomTranscriptionStyle(
                id: "meeting_notes",
                displayName: "Meeting Notes",
                prompt: [
                    "请把这段音频整理成简洁会议纪要。",
                    "保留明确说出的决定、待办、时间、人名、项目名和技术词。",
                    "如果有多个要点，使用简短的换行列表。",
                    "不要新增用户没有说出的事实、结论、负责人或截止日期。"
                ].joined(separator: "\n")
            )
        case .english:
            return CustomTranscriptionStyle(
                id: "meeting_notes",
                displayName: "Meeting Notes",
                prompt: [
                    "Turn this audio into concise meeting notes.",
                    "Preserve explicitly spoken decisions, todos, times, names, project names, and technical terms.",
                    "Use a short line-by-line list when there are multiple points.",
                    "Do not add facts, conclusions, owners, or deadlines that the user did not say."
                ].joined(separator: "\n")
            )
        }
    }

    private static func addComment(_ comment: [String], indent: Int, to lines: inout [String]) {
        let prefix = String(repeating: " ", count: indent) + "// "
        comment.forEach { lines.append(prefix + $0) }
    }

    private static func jsonString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let raw = String(data: data, encoding: .utf8),
              raw.count >= 2 else {
            return "\"\""
        }
        return String(raw.dropFirst().dropLast())
    }

    private static func appendJSONStringArrayProperty(
        name: String,
        values: [String],
        indent: Int,
        trailingComma: Bool,
        to lines: inout [String]
    ) {
        let prefix = String(repeating: " ", count: indent)
        guard !values.isEmpty else {
            lines.append("\(prefix)\(jsonString(name)): []\(trailingComma ? "," : "")")
            return
        }
        lines.append("\(prefix)\(jsonString(name)): [")
        let itemPrefix = String(repeating: " ", count: indent + 2)
        for (index, value) in values.enumerated() {
            lines.append("\(itemPrefix)\(jsonString(value))\(index == values.count - 1 ? "" : ",")")
        }
        lines.append("\(prefix)]\(trailingComma ? "," : "")")
    }
}

private struct ConfigDocumentText {
    let language: UILanguage

    var fileIntro: [String] {
        switch language {
        case .chinese:
            return [
                "OmniVoice 会读取这个文件：~/.config/omnivoice/config.jsonc。",
                "这个文件会覆盖 App 内置默认配置；未写出的字段继续使用默认值。",
                "如果填写了 API Key，请保持本文件权限为 0600。"
            ]
        case .english:
            return [
                "OmniVoice reads this file at ~/.config/omnivoice/config.jsonc.",
                "This file overrides the app's built-in defaults; omitted fields keep default values.",
                "Keep this file at permission 0600 when an API key is filled in."
            ]
        }
    }

    var activeSource: [String] {
        language == .chinese
            ? ["API 来源 ID。使用 \"auto\" 时，OmniVoice 只会在支持当前模型的来源里选择测速最快者。"]
            : ["API source ID. Use \"auto\" to choose the fastest source that exposes the current model."]
    }

    var transcriptionPipeline: [String] {
        language == .chinese
            ? ["转写管线：input_audio 直接把音频交给多模态模型；system_asr_text_llm 先用系统 ASR，再交给文本模型修正；system_asr_only 只使用系统 ASR。"]
            : ["Transcription pipeline: input_audio sends audio directly to an omnimodal model; system_asr_text_llm uses System ASR first, then a text model; system_asr_only uses System ASR only."]
    }

    var transcriptionPipelineMode: [String] {
        language == .chinese
            ? ["可选值：input_audio、system_asr_text_llm、system_asr_only。"]
            : ["Allowed values: input_audio, system_asr_text_llm, system_asr_only."]
    }

    var models: [String] {
        language == .chinese
            ? ["模型目录。audio_llm 保存音频直转候选；text_llm 只保存系统 ASR 草稿后处理的默认模型。"]
            : ["Model catalogs. audio_llm stores direct audio candidates; text_llm only stores the default System ASR cleanup model."]
    }

    var inputAudioDefaultModel: [String] {
        language == .chinese
            ? ["音频直转默认 Audio LLM。默认使用 mimo-v2.5。"]
            : ["Default direct Audio LLM. The default is mimo-v2.5."]
    }

    var inputAudioExtraModels: [String] {
        language == .chinese
            ? ["额外 Audio LLM 候选。菜单只显示这些候选中已被至少一个 API 来源 /v1/models 观测到的模型。"]
            : ["Extra Audio LLM candidates. Menus only show candidates observed from at least one API source via /v1/models."]
    }

    var textLLMDefaultModel: [String] {
        language == .chinese
            ? ["系统 ASR 后处理默认文本模型。可选候选来自当前 API 来源的 /v1/models；如果模型不支持文本补全，请在菜单中更换。"]
            : ["Default text model for System ASR post-processing. Menu candidates come from the current API sources' /v1/models; choose another model if one does not support text completion."]
    }

    var systemASR: [String] {
        language == .chinese
            ? ["系统 ASR 设置。Apple 在线识别是一个显式引擎选项，选择后可能把音频发送给 Apple。"]
            : ["System ASR settings. Apple online recognition is an explicit engine choice and may send audio to Apple."]
    }

    var systemASREngine: [String] {
        language == .chinese
            ? ["识别引擎：speech_analyzer 是默认端侧引擎且需要 macOS 26+；classic_speech 可用于经典端侧识别；apple_online_speech 会允许 Apple 在线识别。"]
            : ["Recognition engine: speech_analyzer is the default on-device engine and requires macOS 26+; classic_speech uses classic on-device recognition; apple_online_speech allows Apple online recognition."]
    }

    var systemASRKeywordHints: [String] {
        language == .chinese
            ? ["是否把启用的关键词组提供给系统 ASR 作为上下文提示。"]
            : ["Whether enabled keyword groups are supplied to System ASR as contextual hints."]
    }

    var sources: [String] {
        language == .chinese
            ? ["API 来源列表。每个 key 是来源 ID，只能使用字母、数字、点、下划线和短横线。"]
            : ["API sources. Each key is a source ID using letters, numbers, dots, underscores, or dashes."]
    }

    func source(_ id: String) -> [String] {
        language == .chinese ? ["来源 \(id)。"] : ["Source \(id)."]
    }

    var baseURL: [String] {
        language == .chinese
            ? ["Base URL 可以带或不带 /v1，OmniVoice 会自动归一化。"]
            : ["Base URL may include /v1; OmniVoice normalizes it automatically."]
    }

    var apiKey: [String] {
        language == .chinese
            ? ["填入这个来源的 API Key。菜单和日志只会显示脱敏状态。"]
            : ["API key for this source. Menus and logs only show redacted status."]
    }

    var latency: [String] {
        language == .chinese
            ? ["测速设置。只访问 /v1/models，不发送语音。"]
            : ["Latency settings. Only /v1/models is called; no voice audio is sent."]
    }

    var latencyEnabled: [String] {
        language == .chinese ? ["是否启用后台测速。"] : ["Whether background latency checks are enabled."]
    }

    var latencyInterval: [String] {
        language == .chinese
            ? ["测速间隔秒数。支持 30、60、120、300、900、1800、3600；null 表示只在启动时测速。"]
            : ["Latency interval in seconds. Supported: 30, 60, 120, 300, 900, 1800, 3600; null means startup only."]
    }

    var preferences: [String] {
        language == .chinese
            ? ["菜单中可设置的用户偏好。OmniVoice 会用这些值同步菜单状态。"]
            : ["User preferences exposed in the menu. OmniVoice syncs menu state from these values."]
    }

    var uiLanguage: [String] {
        language == .chinese ? ["界面语言，同时决定本文件注释语言。"] : ["UI language; also controls the language of comments in this file."]
    }

    var transcriptionStyle: [String] {
        language == .chinese
            ? ["默认转写风格。可使用 concise、verbatim、codeFaithful、rewrite，或 custom:<风格 ID>。"]
            : ["Default transcription style. Use concise, verbatim, codeFaithful, rewrite, or custom:<style ID>."]
    }

    var keywordHintsEnabled: [String] {
        language == .chinese
            ? ["是否启用关键词提示。关闭后不会把任何关键词注入转写 prompt；勾选任一关键词组会自动开启。"]
            : ["Whether keyword hints are enabled. When off, no keywords are injected into the transcription prompt; selecting any group turns this on."]
    }

    var enabledKeywordGroups: [String] {
        language == .chinese
            ? [
                "当前勾选的关键词组 ID。取消最后一个勾选项会自动关闭关键词提示。"
            ]
            : [
                "Selected keyword group IDs. Clearing the final selected group turns keyword hints off."
            ]
    }

    var triggerKey: [String] {
        language == .chinese
            ? ["录音触发键。默认 fn-globe；也可使用菜单中展示的 F1-F12、修饰键或 Caps Lock ID。"]
            : ["Recording trigger key. Default is fn-globe; menu-listed F1-F12, modifier, and Caps Lock IDs are also supported."]
    }

    var continuousRecordingDoubleTap: [String] {
        language == .chinese
            ? ["双击触发键进入持续录音；后续单击触发键停止。默认关闭。Caps Lock 暂不参与双击持续录音。"]
            : ["Double-tap the trigger key to keep recording until the next tap. Off by default. Caps Lock is not used for continuous double-tap recording yet."]
    }

    var minRecording: [String] {
        language == .chinese ? ["最短录音时间，单位毫秒。"] : ["Minimum recording duration in milliseconds."]
    }

    var maxRecording: [String] {
        language == .chinese ? ["最长录音时间，单位秒。"] : ["Maximum recording duration in seconds."]
    }

    var autoInsert: [String] {
        language == .chinese ? ["是否在目标输入框安全可写时自动插入最终文本。"] : ["Whether final text is auto-inserted when the focused field is safe."]
    }

    var launchAtLogin: [String] {
        language == .chinese ? ["是否开机自启。菜单切换时也会同步系统登录项。"] : ["Whether to launch at login. Menu changes also sync the system Login Item."]
    }

    var hud: [String] {
        language == .chinese ? ["HUD 和短提示显示设置。"] : ["HUD and short-message display settings."]
    }

    var hudVisualStyle: [String] {
        language == .chinese
            ? ["HUD 视觉样式：automatic 会跟随系统亮暗外观；也可固定为 darkCapsule、lightCapsule；macOS 26+ 可使用 liquidGlass。"]
            : ["HUD visual style: automatic follows the system light/dark appearance; fixed darkCapsule and lightCapsule are also available; liquidGlass is available on macOS 26+."]
    }

    var hudMessageDuration: [String] {
        language == .chinese ? ["短状态或 warning 提示停留秒数。"] : ["How many seconds short status or warning messages stay visible."]
    }

    var hudRevealDelay: [String] {
        language == .chinese
            ? ["按下触发键后多久显示聆听 HUD，单位毫秒。录音仍会立即开始。"]
            : ["Delay before the listening HUD appears after pressing the trigger, in milliseconds. Recording starts immediately."]
    }

    var liveASRPreview: [String] {
        language == .chinese
            ? ["是否在录音期间用系统语音识别显示实时草稿预览。只影响 HUD 显示，最终文本仍使用所选转写管线。"]
            : ["Whether to show a live System ASR draft in the HUD while recording. This only affects preview; final text still uses the selected pipeline."]
    }

    var customStyles: [String] {
        language == .chinese
            ? ["自定义转写风格，会显示在“风格”菜单和结果面板风格切换中。"]
            : ["Custom transcription styles shown in the Style menu and result-panel style switcher."]
    }

    func customStyle(_ id: String) -> [String] {
        language == .chinese ? ["自定义风格 \(id)。"] : ["Custom style \(id)."]
    }

    var customDisplayName: [String] {
        language == .chinese ? ["显示名。所有界面语言都显示这个名称。"] : ["Display name. The same name is shown in every UI language."]
    }

    var customPromptLines: [String] {
        language == .chinese
            ? ["转写 prompt。写清楚语气、格式和禁止事项，不要要求新增用户没说的事实。"]
            : ["Transcription prompt. State tone, format, and constraints; do not ask for facts the user did not say."]
    }

    var keywordGroups: [String] {
        language == .chinese
            ? ["关键词组会作为识别提示注入 prompt，用于专有名词、产品名、命令、路径和领域术语消歧。"]
            : ["Keyword groups are injected as recognition hints for proper nouns, product names, commands, paths, and domain terms."]
    }

    func keywordGroup(_ id: String) -> [String] {
        language == .chinese ? ["关键词组 \(id)。"] : ["Keyword group \(id)."]
    }

    var keywordDisplayName: [String] {
        language == .chinese
            ? ["显示名。所有界面语言都显示这个名称。"]
            : ["Display name. The same name is shown in every UI language."]
    }

    var keywords: [String] {
        language == .chinese
            ? ["关键词列表。每组最多 200 个；总计最多注入 500 个；不要写换行或控制字符。"]
            : ["Keyword list. Up to 200 per group and 500 injected in total; do not include newlines or control characters."]
    }
}
