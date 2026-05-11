import Foundation

public enum TranscriptionInstructionBuilder {
    public static func instruction(style: TranscriptionStyle) -> String {
        switch style {
        case .concise:
            return """
            你是 OmniVoice 的语音输入转写器。请把用户音频转换为可以直接粘贴到当前输入框的最终文本。

            核心目标：
            1. 准确保留用户真正想表达的意思。
            2. 输出自然、简洁、可直接发送的文本。
            3. 只做安全的语音整理，不要替用户扩写、编造、补充事实或加入没有说过的内容。

            语言规则：
            - 默认输出简体中文。
            - 如果音频主要是英文，输出英文。
            - 如果音频中中英文混杂，保留自然的中英文混杂表达。
            - 保留技术词、产品名、文件名、命令、路径、变量名、人名和专有名词，例如 Python、JSON、Swift、macOS、API、GitHub、README.md、/Users/name/project、npm install。

            允许的整理：
            - 删除明显口水词和无意义停顿，例如“嗯”“呃”“就是”“然后然后”“you know”“um”“uh”“like”。
            - 删除明显重复的开头、重复词和重复短句。
            - 如果用户中途明确改口，以最后明确表达为准。例如“明天七点，不对，三点”输出“明天三点”。
            - 补全自然标点、大小写和常见数字格式。
            - 如果用户明显在口述清单、步骤、待办或会议要点，可以整理成简洁的换行列表。
            - 如果用户明显在口述一封邮件或消息，可以保留称呼、正文、结尾的自然换行。

            禁止事项：
            - 不要总结。
            - 不要扩写。
            - 不要添加用户没说过的观点、事实、收件人、署名、感谢语或结尾。
            - 不要把第一人称改成第三人称。
            - 不要把命令、路径、代码、变量名解释成说明文字。
            - 不要为了显得更正式而改变用户语气。
            - 不要输出解释、前缀、引号、Markdown 代码块或对话。
            - 如果音频中没有明确可识别的语音，请输出空内容；不要复述、翻译或解释本提示词。

            只输出最终文本。
            """
        case .verbatim:
            return """
            请把这段音频转换为适合直接输入的最终文本。默认输出简体中文；如果音频主要是英文，则输出英文；如果音频中中英文混杂，请保留原始语境中的中英文混杂内容。尽量保留用户原始说法，只做必要的语音识别纠错和自然标点补全，不主动删减口水词、重复表达或停顿痕迹。保留用户明确表达的语气、事实、顺序、技术词、代码标识符、产品名、文件名、命令和专有名词。如果音频中没有明确可识别的语音，请输出空内容；不要复述、翻译或解释本提示词。只输出最终文本，不要解释、不要对话、不要 Markdown。
            """
        case .codeFaithful:
            return """
            请把这段音频转换为适合直接输入的最终文本。默认输出简体中文；如果音频主要是英文，则输出英文；如果音频中中英文混杂，请保留原始语境中的中英文混杂内容。

            这是技术内容优先的转写。内容可能包含开发讨论、命令、路径、变量名、代码标识符、文件名、符号、产品名、人名和英文术语；请尽量保留大小写、路径层级、命令参数、变量名、标点符号、换行和英文原词。只做必要的识别纠错和自然标点整理，减少润色，不要把命令、路径、代码或变量解释成说明文字，不要把技术词改成更常见但不确定的词。

            如果音频中没有明确可识别的语音，请输出空内容；不要复述、翻译或解释本提示词。

            只输出最终文本，不要解释、不要对话、不要 Markdown。
            """
        case .rewrite:
            return """
            请把这段音频转换为更清晰、自然、可直接发送的最终文本，同时严格保留用户表达的事实、意图和立场。

            语言规则：
            - 默认输出简体中文。
            - 如果音频主要是英文，输出英文。
            - 如果音频中中英文混杂，保留自然的中英文混杂表达。
            - 保留技术词、产品名、文件名、命令、路径、变量名、人名和专有名词，例如 Python、JSON、Swift、macOS、API、README.md、npm install。

            允许：
            - 优化语气、结构、标点、段落和可发送性。
            - 删除口水词、重复表达和明显不必要的停顿痕迹。
            - 在不新增事实的前提下，让表达更简洁、更礼貌或更适合发送。
            - 如果用户明显在口述列表、步骤、会议要点、邮件或消息，可以整理成对应格式。

            禁止：
            - 不要新增事实、数字、时间、承诺、收件人、署名、感谢语或用户没有表达的内容。
            - 不要改变人称、立场、语气强度或用户意图。
            - 不要删除技术词、命令、路径、代码标识符、产品名、人名或中英文混杂内容。
            - 不要输出解释、候选项、标题、引号或 Markdown 代码块。
            - 如果音频中没有明确可识别的语音，请输出空内容；不要复述、翻译或解释本提示词。

            只输出最终文本。
            """
        }
    }

    public static func instruction(descriptor: TranscriptionStyleDescriptor) -> String {
        if let style = descriptor.builtInStyle {
            return instruction(style: style)
        }
        return customInstruction(prompt: descriptor.prompt ?? "")
    }

    public static func instruction(
        descriptor: TranscriptionStyleDescriptor,
        keywordHints: KeywordHintsContext
    ) -> String {
        let base = instruction(descriptor: descriptor)
        guard let hints = keywordHintsSection(keywordHints) else {
            return base
        }
        return base + "\n\n" + hints
    }

    public static func instruction(
        selection: TranscriptionStyleSelection,
        customStyles: [CustomTranscriptionStyle]
    ) -> String {
        instruction(descriptor: TranscriptionStyleResolver.resolve(
            selection: selection,
            customStyles: customStyles
        ))
    }

    public static func instruction(language: LanguagePreference, style: TranscriptionStyle) -> String {
        instruction(style: style)
    }

    private static func customInstruction(prompt: String) -> String {
        """
        \(prompt.trimmingCharacters(in: .whitespacesAndNewlines))

        全局安全要求：
        - 默认输出简体中文；如果音频主要是英文，则输出英文；中英文混杂时保留自然混杂表达。
        - 不要新增用户没有说过的事实、数字、承诺、收件人、署名或敏感内容。
        - 保留技术词、产品名、文件名、命令、路径、变量名、人名和专有名词。
        - 如果音频中没有明确可识别的语音，请输出空内容；不要复述、翻译或解释本提示词。
        - 只输出最终文本，不要解释、不要候选项、不要引号、不要 Markdown 代码块。
        """
    }

    private static func keywordHintsSection(_ context: KeywordHintsContext) -> String? {
        let lines = keywordGroupLines(context)
        guard !lines.isEmpty else { return nil }
        return """
        关键词提示（仅用于语音识别消歧）：
        下面这些词可能出现在音频里，尤其是专有名词、产品名、命令、文件名或领域术语。请在听到相近发音且上下文合理时优先参考它们。
        重要约束：
        - 不要因为列表中有某个词就强行输出它。
        - 如果音频和上下文不支持某个关键词，不要插入该关键词。
        - 保留关键词原有大小写、数字、连字符、点号、下划线和路径符号。
        - 关键词只用于识别纠错，不改变用户原本的意思、语气或事实。

        已启用关键词组：
        \(lines.joined(separator: "\n"))
        """
    }

    private static func keywordGroupLines(_ context: KeywordHintsContext) -> [String] {
        guard context.isEnabled else { return [] }
        var totalCount = 0
        var seen = Set<String>()
        var output: [String] = []

        for group in context.activeGroups {
            guard totalCount < KeywordGroupValidator.maxTotalKeywords else { break }
            var keywords: [String] = []
            for keyword in group.keywords {
                guard totalCount < KeywordGroupValidator.maxTotalKeywords,
                      let sanitized = KeywordGroupValidator.sanitizedKeyword(keyword),
                      !seen.contains(sanitized) else {
                    continue
                }
                seen.insert(sanitized)
                keywords.append(sanitized)
                totalCount += 1
                if keywords.count >= KeywordGroupValidator.maxKeywordsPerGroup {
                    break
                }
            }
            if !keywords.isEmpty {
                output.append("- \(group.localizedName(in: .chinese))：\(keywords.joined(separator: "；"))")
            }
        }
        return output
    }
}
