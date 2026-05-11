import Foundation

enum DefaultConfigFactory {
    static func config(uiLanguage: UILanguage) -> MimoConfig {
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
            preferences: .defaultPreferences(selectedModel: .defaultInputAudioModel, uiLanguage: uiLanguage)
        )
    }

    static func defaultKeywordGroups(uiLanguage: UILanguage) -> [KeywordGroup] {
        let llmGroup = KeywordGroup(
            id: "llm_model_terms",
            displayName: uiLanguage == .chinese ? "大模型与模型公司" : "LLM Models and Companies",
            keywords: llmModelKeywords
        )
        switch uiLanguage {
        case .chinese:
            return [
                KeywordGroup(
                    id: "mimo_e2e_terms",
                    displayName: "MiMo E2E Terms",
                    keywords: commonMimoKeywords
                ),
                KeywordGroup(
                    id: "omnivoice_terms",
                    displayName: "OmniVoice 术语",
                    keywords: commonOmniVoiceKeywords
                ),
                KeywordGroup(
                    id: "technical_terms",
                    displayName: "技术术语",
                    keywords: commonTechnicalKeywords
                ),
                llmGroup
            ]
        case .english:
            return [
                KeywordGroup(
                    id: "mimo_e2e_terms",
                    displayName: "MiMo E2E Terms",
                    keywords: commonMimoKeywords
                ),
                KeywordGroup(
                    id: "omnivoice_terms",
                    displayName: "OmniVoice Terms",
                    keywords: commonOmniVoiceKeywords
                ),
                KeywordGroup(
                    id: "technical_terms",
                    displayName: "Technical Terms",
                    keywords: commonTechnicalKeywords
                ),
                llmGroup
            ]
        }
    }

    static let llmModelKeywords = [
        "OpenAI",
        "ChatGPT",
        "GPT",
        "Anthropic",
        "Claude",
        "Claude Code",
        "Opus",
        "Sonnet",
        "Haiku",
        "Google",
        "Gemini",
        "Gemma",
        "Llama",
        "Mistral",
        "xAI",
        "Grok",
        "Qwen",
        "Qwen3",
        "Qwen3.5",
        "Qwen3.6",
        "Qwen Omni",
        "DeepSeek",
        "Kimi",
        "MiniMax",
        "Zhipu AI",
        "智谱",
        "GLM",
        "Hunyuan",
        "StepFun",
        "阶跃星辰",
        "SenseNova",
        "Hermes",
        "OpenClaw",
        "Hugging Face"
    ]

    static let commonMimoKeywords = [
        "OmniVoice",
        "MiMo",
        "mimo-v2.5",
        "mimo-v2-omni",
        "mimo-v2-pro",
        "mimo-v2.5-pro",
        "config.jsonc",
        "Swift",
        "API"
    ]

    static let commonOmniVoiceKeywords = [
        "OmniVoice",
        "MiMo",
        "mimo-v2.5",
        "mimo-v2-omni",
        "mimo-v2-pro",
        "mimo-v2.5-pro",
        "config.jsonc",
        "ActionPanel",
        "HUD",
        "Panel"
    ]

    static let commonTechnicalKeywords = [
        "Swift",
        "AppKit",
        "macOS",
        "JSONC",
        "API",
        "make run",
        "Cmd+V",
        "Fn"
    ]

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
}
