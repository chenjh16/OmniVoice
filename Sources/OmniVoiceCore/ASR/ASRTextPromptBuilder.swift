import Foundation

public enum ASRTextPromptBuilder {
    public static func prompt(
        asrResult: ASRRecognitionResult,
        styleDescriptor: TranscriptionStyleDescriptor,
        keywordHints: KeywordHintsContext
    ) -> String {
        let keywords = SystemASRKeywordPlanner.contextualStrings(from: keywordHints)
        return """
        你是 OmniVoice 的语音输入后处理器。下面的输入不是用户直接键入的文字，而是 macOS 系统 ASR 生成的草稿，可靠性有限。

        ASR 草稿可能包含：
        - 同音词错误、专有名词错误、产品名错误、代码术语错误。
        - 标点缺失、断句错误、漏词、多词或片段顺序不自然。
        - 中英文混杂内容、命令、路径、API、文件名、变量名被错误改写。

        你的任务：
        1. 根据 ASR 草稿、低置信片段、候选词和关键词提示，纠正明显识别错误。
        2. 严格保留用户实际表达的事实、意图、人称、语气强度和技术细节。
        3. 当草稿含糊且无法可靠判断时，不要编造；保留更保守的表达。
        4. 只输出最终可粘贴文本，不要解释、不要候选项、不要 Markdown 代码块。

        风格要求：
        \(styleInstruction(styleDescriptor))

        关键词提示（仅用于纠错，不要强行输出）：
        \(keywords.isEmpty ? "（无）" : keywords.joined(separator: "；"))

        ASR 低置信片段和候选：
        \(lowConfidenceSection(asrResult.lowConfidenceSegments))

        ASR 全句候选：
        \(asrResult.alternatives.isEmpty ? "（无）" : asrResult.alternatives.joined(separator: "\n"))

        <asr_draft>
        \(asrResult.text)
        </asr_draft>
        """
    }

    private static func customStyleInstruction(_ descriptor: TranscriptionStyleDescriptor) -> String {
        """
        自定义风格「\(descriptor.displayName)」：在不新增事实、不改变意图的前提下应用以下要求。
        \(descriptor.prompt ?? "")
        """
    }

    private static func styleInstruction(_ descriptor: TranscriptionStyleDescriptor) -> String {
        guard let style = descriptor.builtInStyle else {
            return customStyleInstruction(descriptor)
        }
        switch style {
        case .verbatim:
            return "尽量贴近 ASR 草稿和用户原话，只修正清楚的识别错误、标点和大小写；不要主动删减口水词、重复和停顿痕迹。"
        case .concise:
            return "输出自然、简洁、可直接发送的文本。删除明显口水词、重复表达和无意义停顿；处理明确改口；不要扩写、总结或添加事实。"
        case .codeFaithful:
            return "技术内容优先。积极纠正可能被 ASR 听错的命令、路径、API、文件名、变量、产品名和中英文术语；保留大小写、符号和换行。"
        case .rewrite:
            return "在不新增事实、不改变意图的前提下，优化结构、语气、段落和可发送性；不要添加收件人、署名、承诺、数字或用户没说过的内容。"
        }
    }

    private static func lowConfidenceSection(_ segments: [ASRSegmentAlternative]) -> String {
        guard !segments.isEmpty else { return "（无）" }
        return segments.prefix(20).map { segment in
            let alternatives = segment.alternatives.isEmpty ? "无候选" : segment.alternatives.joined(separator: " / ")
            return "- \(segment.text)（confidence \(String(format: "%.2f", segment.confidence))）：\(alternatives)"
        }.joined(separator: "\n")
    }
}
