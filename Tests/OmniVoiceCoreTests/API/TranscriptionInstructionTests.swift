import Foundation
import ApplicationServices
import Testing
@testable import OmniVoiceCore

@Suite("Transcription instructions")
struct TranscriptionInstructionTests {
    @Test
    func progressEstimatorUsesRecordingLengthAndCaps() {
        #expect(abs(TranscriptionProgressEstimator.estimatedProcessingSeconds(for: 10) - 8) < 0.001)
        #expect(abs(TranscriptionProgressEstimator.estimatedProcessingSeconds(for: 60) - 38) < 0.001)
        #expect(abs(TranscriptionProgressEstimator.estimatedProcessingSeconds(for: 200) - 45) < 0.001)

        let ten = TranscriptionProgressEstimator(recordingSeconds: 10)
        let sixty = TranscriptionProgressEstimator(recordingSeconds: 60)
        #expect(ten.progress(elapsedSeconds: 4, hasReceivedDelta: false, isFinished: false) > 0.35)
        #expect(sixty.progress(elapsedSeconds: 4, hasReceivedDelta: false, isFinished: false) < 0.2)
        #expect(ten.progress(elapsedSeconds: 60, hasReceivedDelta: false, isFinished: false) <= 0.88)
        #expect(ten.progress(elapsedSeconds: 1, hasReceivedDelta: true, isFinished: false, deltaChunkCount: 1, deltaCharacterCount: 2) >= 0.50)
        #expect(ten.progress(elapsedSeconds: 60, hasReceivedDelta: true, isFinished: false, deltaChunkCount: 100, deltaCharacterCount: 500) <= 0.95)
        #expect(ten.progress(elapsedSeconds: 0, hasReceivedDelta: true, isFinished: true) == 1.0)
    }
    @Test
    func instructionBuilderIncludesLanguageAndStyleConstraints() {
        let concise = TranscriptionInstructionBuilder.instruction(style: .concise)
        #expect(concise.contains("默认输出简体中文"))
        #expect(concise.contains("音频主要是英文"))
        #expect(concise.contains("Python"))
        #expect(concise.contains("不要扩写"))
        #expect(concise.contains("最后明确表达"))
        #expect(concise.contains("清单"))
        #expect(concise.contains("不要添加用户没说过"))

        let verbatim = TranscriptionInstructionBuilder.instruction(style: .verbatim)
        #expect(verbatim.contains("保留用户原始说法"))
        #expect(verbatim.contains("不主动删减"))

        let code = TranscriptionInstructionBuilder.instruction(style: .codeFaithful)
        #expect(code.contains("大小写"))
        #expect(code.contains("路径"))
        #expect(code.contains("命令参数"))
        #expect(code.contains("不要把命令"))

        let rewrite = TranscriptionInstructionBuilder.instruction(style: .rewrite)
        #expect(rewrite.contains("优化语气"))
        #expect(rewrite.contains("不要新增事实"))
        #expect(rewrite.contains("承诺"))

        let custom = CustomTranscriptionStyle(
            id: "support_reply",
            displayName: "Support Reply",
            prompt: "请整理成简短客服回复。"
        )
        let customInstruction = TranscriptionInstructionBuilder.instruction(
            selection: .custom("support_reply"),
            customStyles: [custom]
        )
        #expect(customInstruction.contains("请整理成简短客服回复"))
        #expect(customInstruction.contains("全局安全要求"))

        let descriptor = TranscriptionStyleResolver.resolve(
            selection: .custom("support_reply"),
            customStyles: [custom]
        )
        let keywordGroup = KeywordGroup(
            id: "omnivoice_terms",
            displayName: "OmniVoice Terms",
            keywords: ["OmniVoice", "MiMo", "MiMo", " bad\nkeyword "]
        )
        let keywordInstruction = TranscriptionInstructionBuilder.instruction(
            descriptor: descriptor,
            keywordHints: KeywordHintsContext(isEnabled: true, groups: [keywordGroup])
        )
        #expect(keywordInstruction.contains("请整理成简短客服回复"))
        #expect(keywordInstruction.contains("关键词提示（仅用于语音识别消歧）"))
        #expect(keywordInstruction.contains("不要因为列表中有某个词就强行输出它"))
        #expect(keywordInstruction.contains("- OmniVoice Terms：OmniVoice；MiMo"))
        #expect(!keywordInstruction.contains("bad\nkeyword"))

        let disabledKeywordInstruction = TranscriptionInstructionBuilder.instruction(
            descriptor: descriptor,
            keywordHints: KeywordHintsContext(isEnabled: false, groups: [keywordGroup])
        )
        #expect(!disabledKeywordInstruction.contains("关键词提示"))

        let legacyChinese = TranscriptionInstructionBuilder.instruction(language: .simplifiedChinese, style: .concise)
        let legacyEnglish = TranscriptionInstructionBuilder.instruction(language: .english, style: .concise)
        #expect(legacyChinese == legacyEnglish)
    }
    @Test
    func asrTextPromptIncludesUnreliableDraftWarningAlternativesAndStyleRules() {
        let asr = ASRRecognitionResult(
            text: "把 open ai 的 g p t audio 写到 read me",
            lowConfidenceSegments: [
                ASRSegmentAlternative(text: "open ai", alternatives: ["OpenAI"], confidence: 0.42)
            ],
            alternatives: ["把 OpenAI 的 GPT Audio 写到 README"],
            allowedAppleServerRecognition: false
        )
        let descriptor = TranscriptionStyleResolver.builtInDescriptor(.codeFaithful)
        let keywordGroup = KeywordGroup(
            id: "terms",
            displayName: "Terms",
            keywords: ["OpenAI", "GPT Audio", "README.md", "bad\nkeyword"]
        )
        let prompt = ASRTextPromptBuilder.prompt(
            asrResult: asr,
            styleDescriptor: descriptor,
            keywordHints: KeywordHintsContext(isEnabled: true, groups: [keywordGroup])
        )

        #expect(prompt.contains("ASR 生成的草稿，可靠性有限"))
        #expect(prompt.contains("同音词错误"))
        #expect(prompt.contains("OpenAI"))
        #expect(prompt.contains("GPT Audio"))
        #expect(prompt.contains("README.md"))
        #expect(prompt.contains("confidence 0.42"))
        #expect(prompt.contains("把 OpenAI 的 GPT Audio 写到 README"))
        #expect(prompt.contains("<asr_draft>"))
        #expect(prompt.contains("技术内容优先"))
        #expect(!prompt.contains("bad\nkeyword"))

        let hints = SystemASRKeywordPlanner.contextualStrings(from: KeywordHintsContext(
            isEnabled: true,
            groups: [
                KeywordGroup(id: "many", keywords: (0..<120).map { "term\($0)" } + ["too many words here"])
            ]
        ))
        #expect(hints.count == KeywordGroupValidator.maxASRContextualStrings)
        #expect(!hints.contains("too many words here"))
    }
}
