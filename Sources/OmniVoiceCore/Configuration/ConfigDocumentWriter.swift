import Foundation

enum ConfigDocumentWriter {
    static func defaultDocument(uiLanguage: UILanguage) -> String {
        document(config: DefaultConfigFactory.config(uiLanguage: uiLanguage), uiLanguage: uiLanguage)
    }

    static func document(config: MimoConfig, uiLanguage: UILanguage) -> String {
        let text = ConfigDocumentText(language: uiLanguage)
        var lines: [String] = ["{"]

        appendHeaderAndActiveSource(config, text: text, to: &lines)
        appendPipeline(config, text: text, to: &lines)
        appendModels(config, text: text, to: &lines)
        appendSystemASR(config, text: text, to: &lines)
        appendSources(config, text: text, to: &lines)
        appendLatency(config, text: text, to: &lines)
        appendPreferences(config, uiLanguage: uiLanguage, text: text, to: &lines)
        appendCustomStyles(config, text: text, to: &lines)
        appendKeywordGroups(config, text: text, to: &lines)
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func appendHeaderAndActiveSource(
        _ config: MimoConfig,
        text: ConfigDocumentText,
        to lines: inout [String]
    ) {
        addComment(text.fileIntro, indent: 2, to: &lines)
        addComment(text.activeSource, indent: 2, to: &lines)
        lines.append("  \(jsonString(ConfigSchema.Root.activeSource)): \(jsonString(config.activeSourceID)),")
    }

    private static func appendPipeline(
        _ config: MimoConfig,
        text: ConfigDocumentText,
        to lines: inout [String]
    ) {
        addComment(text.transcriptionPipeline, indent: 2, to: &lines)
        lines.append("  \(jsonString(ConfigSchema.Root.transcriptionPipeline)): {")
        addComment(text.transcriptionPipelineMode, indent: 4, to: &lines)
        lines.append("    \(jsonString(ConfigSchema.Pipeline.mode)): \(jsonString(config.pipelineMode.rawValue))")
        lines.append("  },")
    }

    private static func appendModels(
        _ config: MimoConfig,
        text: ConfigDocumentText,
        to lines: inout [String]
    ) {
        addComment(text.models, indent: 2, to: &lines)
        lines.append("  \(jsonString(ConfigSchema.Root.models)): {")
        lines.append("    \(jsonString(ConfigSchema.Models.audioLLM)): {")
        addComment(text.inputAudioDefaultModel, indent: 6, to: &lines)
        lines.append("      \(jsonString(ConfigSchema.Models.defaultModel)): \(jsonString(config.modelCatalogs.inputAudioDefaultModel.rawValue)),")
        addComment(text.inputAudioExtraModels, indent: 6, to: &lines)
        appendJSONStringArrayProperty(
            name: ConfigSchema.Models.extraModels,
            values: config.modelCatalogs.inputAudioExtraModels.map(\.rawValue),
            indent: 6,
            trailingComma: false,
            to: &lines
        )
        lines.append("    },")
        lines.append("    \(jsonString(ConfigSchema.Models.textLLM)): {")
        addComment(text.textLLMDefaultModel, indent: 6, to: &lines)
        lines.append("      \(jsonString(ConfigSchema.Models.defaultModel)): \(jsonString(config.modelCatalogs.textLLMDefaultModel.rawValue))")
        lines.append("    }")
        lines.append("  },")
    }

    private static func appendSystemASR(
        _ config: MimoConfig,
        text: ConfigDocumentText,
        to lines: inout [String]
    ) {
        addComment(text.systemASR, indent: 2, to: &lines)
        lines.append("  \(jsonString(ConfigSchema.Root.systemASR)): {")
        addComment(text.systemASREngine, indent: 4, to: &lines)
        lines.append("    \(jsonString(ConfigSchema.SystemASR.engine)): \(jsonString(config.systemASRSettings.engine.rawValue)),")
        addComment(text.systemASRKeywordHints, indent: 4, to: &lines)
        lines.append("    \(jsonString(ConfigSchema.SystemASR.keywordHintsEnabled)): \(config.systemASRSettings.keywordHintsEnabled ? "true" : "false")")
        lines.append("  },")
    }

    private static func appendSources(
        _ config: MimoConfig,
        text: ConfigDocumentText,
        to lines: inout [String]
    ) {
        addComment(text.sources, indent: 2, to: &lines)
        lines.append("  \(jsonString(ConfigSchema.Root.sources)): {")
        let sources = config.sources.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        for (index, source) in sources.enumerated() {
            addComment(text.source(source.id), indent: 4, to: &lines)
            lines.append("    \(jsonString(source.id)): {")
            addComment(text.baseURL, indent: 6, to: &lines)
            lines.append("      \(jsonString(ConfigSchema.Source.baseURL)): \(jsonString(source.baseURL.absoluteString)),")
            addComment(text.apiKey, indent: 6, to: &lines)
            lines.append("      \(jsonString(ConfigSchema.Source.apiKey)): \(jsonString(source.apiKey ?? ""))")
            lines.append("    }\(index == sources.count - 1 ? "" : ",")")
        }
        lines.append("  },")
    }

    private static func appendLatency(
        _ config: MimoConfig,
        text: ConfigDocumentText,
        to lines: inout [String]
    ) {
        addComment(text.latency, indent: 2, to: &lines)
        lines.append("  \(jsonString(ConfigSchema.Root.latency)): {")
        addComment(text.latencyEnabled, indent: 4, to: &lines)
        lines.append("    \(jsonString(ConfigSchema.Latency.enabled)): \(config.latencySettings.interval == .off ? "false" : "true"),")
        addComment(text.latencyInterval, indent: 4, to: &lines)
        if let seconds = config.latencySettings.interval.seconds {
            lines.append("    \(jsonString(ConfigSchema.Latency.intervalSeconds)): \(seconds)")
        } else {
            lines.append("    \(jsonString(ConfigSchema.Latency.intervalSeconds)): null")
        }
        lines.append("  },")
    }

    private static func appendPreferences(
        _ config: MimoConfig,
        uiLanguage: UILanguage,
        text: ConfigDocumentText,
        to lines: inout [String]
    ) {
        let preferences = config.preferences.with(selectedModel: config.modelCatalogs.inputAudioDefaultModel, uiLanguage: uiLanguage)
        addComment(text.preferences, indent: 2, to: &lines)
        lines.append("  \(jsonString(ConfigSchema.Root.preferences)): {")
        addComment(text.uiLanguage, indent: 4, to: &lines)
        lines.append("    \(jsonString(ConfigSchema.Preferences.uiLanguage)): \(jsonString(preferences.uiLanguage.rawValue)),")
        addComment(text.transcriptionStyle, indent: 4, to: &lines)
        lines.append("    \(jsonString(ConfigSchema.Preferences.transcriptionStyle)): \(jsonString(preferences.transcriptionStyleSelection.rawValue)),")
        addComment(text.keywordHintsEnabled, indent: 4, to: &lines)
        lines.append("    \(jsonString(ConfigSchema.Preferences.keywordHintsEnabled)): \(preferences.keywordHintsEnabled ? "true" : "false"),")
        addComment(text.enabledKeywordGroups, indent: 4, to: &lines)
        appendJSONStringArrayProperty(
            name: ConfigSchema.Preferences.enabledKeywordGroups,
            values: preferences.enabledKeywordGroupIDs,
            indent: 4,
            trailingComma: true,
            to: &lines
        )
        addComment(text.triggerKey, indent: 4, to: &lines)
        lines.append("    \(jsonString(ConfigSchema.Preferences.triggerKey)): \(jsonString(preferences.triggerKey.identifier)),")
        addComment(text.continuousRecordingDoubleTap, indent: 4, to: &lines)
        lines.append("    \(jsonString(ConfigSchema.Preferences.trigger)): {")
        lines.append("      \(jsonString(ConfigSchema.Trigger.continuousRecordingDoubleTapEnabled)): \(preferences.continuousRecordingDoubleTapEnabled ? "true" : "false")")
        lines.append("    },")
        addComment(text.minRecording, indent: 4, to: &lines)
        lines.append("    \(jsonString(ConfigSchema.Preferences.minRecordingDurationMS)): \(preferences.minRecordingDuration.rawValue),")
        addComment(text.maxRecording, indent: 4, to: &lines)
        lines.append("    \(jsonString(ConfigSchema.Preferences.maxRecordingDurationSeconds)): \(preferences.maxRecordingDuration.rawValue),")
        addComment(text.autoInsert, indent: 4, to: &lines)
        lines.append("    \(jsonString(ConfigSchema.Preferences.autoInsert)): \(preferences.autoInsert ? "true" : "false"),")
        addComment(text.launchAtLogin, indent: 4, to: &lines)
        lines.append("    \(jsonString(ConfigSchema.Preferences.launchAtLogin)): \(preferences.launchAtLogin ? "true" : "false"),")
        addComment(text.hud, indent: 4, to: &lines)
        lines.append("    \(jsonString(ConfigSchema.Preferences.hud)): {")
        addComment(text.hudVisualStyle, indent: 6, to: &lines)
        lines.append("      \(jsonString(ConfigSchema.HUD.visualStyle)): \(jsonString(preferences.hudVisualStyle.rawValue)),")
        addComment(text.hudMessageDuration, indent: 6, to: &lines)
        lines.append("      \(jsonString(ConfigSchema.HUD.messageDurationSeconds)): \(preferences.hudMessageDuration.rawValue),")
        addComment(text.hudRevealDelay, indent: 6, to: &lines)
        lines.append("      \(jsonString(ConfigSchema.HUD.revealDelayMS)): \(preferences.hudRevealDelay.rawValue),")
        addComment(text.liveASRPreview, indent: 6, to: &lines)
        lines.append("      \(jsonString(ConfigSchema.HUD.liveASRPreviewEnabled)): \(preferences.liveASRPreviewEnabled ? "true" : "false")")
        lines.append("    }")
        lines.append("  },")
    }

    private static func appendCustomStyles(
        _ config: MimoConfig,
        text: ConfigDocumentText,
        to lines: inout [String]
    ) {
        addComment(text.customStyles, indent: 2, to: &lines)
        lines.append("  \(jsonString(ConfigSchema.Root.customStyles)): {")
        let styles = config.customStyles.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        for (index, style) in styles.enumerated() {
            addComment(text.customStyle(style.id), indent: 4, to: &lines)
            lines.append("    \(jsonString(style.id)): {")
            addComment(text.customDisplayName, indent: 6, to: &lines)
            lines.append("      \(jsonString(ConfigSchema.CustomStyle.displayName)): \(jsonString(style.displayName)),")
            addComment(text.customPromptLines, indent: 6, to: &lines)
            let promptLines = style.prompt.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            appendJSONStringArrayProperty(
                name: ConfigSchema.CustomStyle.promptLines,
                values: promptLines,
                indent: 6,
                trailingComma: false,
                to: &lines
            )
            lines.append("    }\(index == styles.count - 1 ? "" : ",")")
        }
        lines.append("  },")
    }

    private static func appendKeywordGroups(
        _ config: MimoConfig,
        text: ConfigDocumentText,
        to lines: inout [String]
    ) {
        addComment(text.keywordGroups, indent: 2, to: &lines)
        lines.append("  \(jsonString(ConfigSchema.Root.keywordGroups)): {")
        let keywordGroups = config.keywordGroups.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        for (index, group) in keywordGroups.enumerated() {
            addComment(text.keywordGroup(group.id), indent: 4, to: &lines)
            lines.append("    \(jsonString(group.id)): {")
            addComment(text.keywordDisplayName, indent: 6, to: &lines)
            lines.append("      \(jsonString(ConfigSchema.KeywordGroup.displayName)): \(jsonString(group.displayName ?? group.id)),")
            addComment(text.keywords, indent: 6, to: &lines)
            appendJSONStringArrayProperty(
                name: ConfigSchema.KeywordGroup.keywords,
                values: group.keywords,
                indent: 6,
                trailingComma: false,
                to: &lines
            )
            lines.append("    }\(index == keywordGroups.count - 1 ? "" : ",")")
        }
        lines.append("  }")
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
            ? ["是否在录音期间把系统语音识别文本显示到 HUD。关闭后，音频直转仍可能在后台使用系统语音识别做本地有效语音预判。"]
            : ["Whether to show live System ASR text in the HUD while recording. When off, Direct Audio may still use system speech in the background for local reliable-speech checks."]
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
