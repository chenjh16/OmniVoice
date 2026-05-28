import Foundation
import Testing
@testable import OmniVoiceCore

@Suite("Live ASR transcript accumulator")
struct LiveASRTranscriptAccumulatorTests {
    @Test
    func accumulatesSegmentsAfterLongPause() {
        var accumulator = LiveASRTranscriptAccumulator(segmentPauseThreshold: 1.2)
        let start = Date(timeIntervalSince1970: 0)

        let first = accumulator.accept(
            LiveASRUpdate(text: "第一段内容", isFinal: false),
            now: start
        )
        #expect(first?.displayText == "第一段内容")

        let second = accumulator.accept(
            LiveASRUpdate(text: "第二段内容", isFinal: false),
            now: start.addingTimeInterval(1.4)
        )
        #expect(second?.displayText == "第一段内容第二段内容")
        #expect(accumulator.snapshotForFinal().resolvedText == "第一段内容第二段内容")
    }

    @Test
    func accumulatesUnrelatedResetWithoutWaitingForPauseThreshold() {
        var accumulator = LiveASRTranscriptAccumulator(segmentPauseThreshold: 1.2)
        let start = Date(timeIntervalSince1970: 5)

        _ = accumulator.accept(
            LiveASRUpdate(text: "第一段内容", isFinal: false),
            now: start
        )
        let second = accumulator.accept(
            LiveASRUpdate(text: "第二段内容", isFinal: false),
            now: start.addingTimeInterval(0.2)
        )

        #expect(second?.displayText == "第一段内容第二段内容")
        #expect(accumulator.snapshotForFinal().resolvedText == "第一段内容第二段内容")
    }

    @Test
    func correctionUpdatesSameWorkingSegmentWithoutDuplication() {
        var accumulator = LiveASRTranscriptAccumulator(segmentPauseThreshold: 1.2)
        let start = Date(timeIntervalSince1970: 10)

        _ = accumulator.accept(
            LiveASRUpdate(text: "config json", isFinal: false),
            now: start
        )
        let corrected = accumulator.accept(
            LiveASRUpdate(text: "config jsonc file", isFinal: false),
            now: start.addingTimeInterval(0.2)
        )

        #expect(corrected?.displayText == "config jsonc file")
        #expect(accumulator.snapshotForFinal().resolvedText == "config jsonc file")
    }

    @Test
    func shorterCorrectionDoesNotShrinkDisplayButUpdatesResolvedText() {
        var accumulator = LiveASRTranscriptAccumulator(segmentPauseThreshold: 1.2)
        let start = Date(timeIntervalSince1970: 12)

        _ = accumulator.accept(
            LiveASRUpdate(text: "重构重写的点", isFinal: false),
            now: start
        )
        let corrected = accumulator.accept(
            LiveASRUpdate(text: "重构重写", isFinal: false),
            now: start.addingTimeInterval(0.2)
        )

        #expect(corrected?.displayText == "重构重写的点")
        #expect(corrected?.resolvedText == "重构重写")
        #expect(accumulator.snapshotForFinal().displayText == "重构重写的点")
        #expect(accumulator.snapshot().resolvedText == "重构重写")
    }

    @Test
    func replacementUpdateOverwritesCurrentWorkingSegment() {
        var accumulator = LiveASRTranscriptAccumulator(segmentPauseThreshold: 1.2)
        let start = Date(timeIntervalSince1970: 13)

        _ = accumulator.accept(
            LiveASRUpdate(text: "Id. Claude Code. Google Voice.", isFinal: false),
            now: start
        )
        let corrected = accumulator.accept(
            LiveASRUpdate(
                text: "Claude Code, Google Voice.",
                isFinal: false,
                replacesCurrentSegment: true
            ),
            now: start.addingTimeInterval(0.2)
        )

        #expect(corrected?.displayText == "Claude Code, Google Voice.")
        #expect(corrected?.resolvedText == "Claude Code, Google Voice.")
        #expect(accumulator.snapshotForFinal().displayText == "Claude Code, Google Voice.")
    }

    @Test
    func emptyUpdateDoesNotClearExistingDisplayText() {
        var accumulator = LiveASRTranscriptAccumulator(segmentPauseThreshold: 1.2)
        let start = Date(timeIntervalSince1970: 14)

        _ = accumulator.accept(
            LiveASRUpdate(text: "已有预览", isFinal: false),
            now: start
        )
        let empty = accumulator.accept(
            LiveASRUpdate(text: "   \n\t  ", isFinal: false),
            now: start.addingTimeInterval(0.2)
        )

        #expect(empty == nil)
        #expect(accumulator.snapshot().displayText == "已有预览")
        #expect(accumulator.snapshot().resolvedText == "已有预览")
    }

    @Test
    func fullTranscriptUpdateDoesNotDuplicateCommittedSegment() {
        var accumulator = LiveASRTranscriptAccumulator(segmentPauseThreshold: 1.2)
        let start = Date(timeIntervalSince1970: 20)

        _ = accumulator.accept(
            LiveASRUpdate(text: "第一段内容", isFinal: true),
            now: start
        )
        let full = accumulator.accept(
            LiveASRUpdate(text: "第一段内容 第二段内容", isFinal: false),
            now: start.addingTimeInterval(1.5)
        )

        #expect(full?.displayText == "第一段内容第二段内容")
        #expect(accumulator.snapshotForFinal().resolvedText == "第一段内容第二段内容")
    }

    @Test
    func finalResolverUsesAccumulatedTextWhenSessionReturnsOnlyLastSegment() {
        let snapshot = LiveASRTranscriptSnapshot(
            displayText: "第一段内容第二段内容",
            resolvedText: "第一段内容第二段内容"
        )
        let result = LiveASRFinalTextResolver.resolve(
            sessionResult: ASRRecognitionResult(text: "第二段内容"),
            snapshot: snapshot
        )

        #expect(result.text == "第一段内容第二段内容")
    }

    @Test
    func finalResolverKeepsSessionFinalWhenItAlreadyContainsFullTranscript() {
        let snapshot = LiveASRTranscriptSnapshot(
            displayText: "第一段内容第二段内容",
            resolvedText: "第一段内容第二段内容"
        )
        let result = LiveASRFinalTextResolver.resolve(
            sessionResult: ASRRecognitionResult(text: "第一段内容。第二段内容。"),
            snapshot: snapshot
        )

        #expect(result.text == "第一段内容。第二段内容。")
    }

    @Test
    func finalResolverMergesSuffixPrefixOverlap() {
        let text = LiveASRFinalTextResolver.resolvedText(
            sessionText: "world again",
            accumulatedText: "hello world"
        )

        #expect(text == "hello world again")
    }

    @Test
    func mixedChineseEnglishSegmentsKeepReadableSpacing() {
        var accumulator = LiveASRTranscriptAccumulator(segmentPauseThreshold: 1.2)
        let start = Date(timeIntervalSince1970: 30)

        _ = accumulator.accept(
            LiveASRUpdate(text: "打开 config.jsonc", isFinal: false),
            now: start
        )
        let next = accumulator.accept(
            LiveASRUpdate(text: "然后运行 make run", isFinal: false),
            now: start.addingTimeInterval(1.6)
        )

        #expect(next?.displayText == "打开 config.jsonc 然后运行 make run")
    }
}
