import Foundation

struct LiveASRTranscriptSnapshot: Equatable, Sendable {
    static let empty = LiveASRTranscriptSnapshot(displayText: "", resolvedText: "")

    let displayText: String
    let resolvedText: String

    var isEmpty: Bool {
        displayText.isEmpty && resolvedText.isEmpty
    }
}

struct LiveASRTranscriptAccumulator: Equatable, Sendable {
    static let defaultSegmentPauseThreshold: TimeInterval = 1.2

    private var committedSegments: [String] = []
    private var workingSegment = ""
    private var lastUpdateDate: Date?
    private let segmentPauseThreshold: TimeInterval

    init(segmentPauseThreshold: TimeInterval = Self.defaultSegmentPauseThreshold) {
        self.segmentPauseThreshold = segmentPauseThreshold
    }

    mutating func reset() {
        committedSegments.removeAll(keepingCapacity: true)
        workingSegment = ""
        lastUpdateDate = nil
    }

    mutating func accept(_ update: LiveASRUpdate, now: Date = Date()) -> LiveASRTranscriptSnapshot? {
        let text = Self.displayText(update.text)
        guard !text.isEmpty else { return nil }

        var candidate = candidateWithoutCommittedPrefix(text)
        if candidate.isEmpty {
            workingSegment = ""
            lastUpdateDate = now
            return snapshot()
        }

        if shouldCommitWorking(before: candidate, now: now) {
            commitWorkingSegment()
            candidate = candidateWithoutCommittedPrefix(text)
            if candidate.isEmpty {
                lastUpdateDate = now
                return snapshot()
            }
        }

        workingSegment = candidate
        if update.isFinal {
            commitWorkingSegment()
        }
        lastUpdateDate = now
        return snapshot()
    }

    mutating func snapshotForFinal() -> LiveASRTranscriptSnapshot {
        commitWorkingSegment()
        return snapshot()
    }

    func snapshot() -> LiveASRTranscriptSnapshot {
        let display = Self.combinedText(segments: committedSegments, working: workingSegment)
        return LiveASRTranscriptSnapshot(displayText: display, resolvedText: display)
    }

    static func displayText(_ text: String) -> String {
        HUDLivePreviewPresentationPlanner.displayText(from: text)
    }

    private func candidateWithoutCommittedPrefix(_ text: String) -> String {
        let committed = Self.combinedText(segments: committedSegments, working: "")
        guard !committed.isEmpty else { return text }
        if Self.equivalent(text, committed) {
            return ""
        }
        guard text.hasPrefix(committed) else { return text }
        let suffix = String(text.dropFirst(committed.count))
        return Self.displayText(suffix)
    }

    private func shouldCommitWorking(before candidate: String, now: Date) -> Bool {
        guard !workingSegment.isEmpty,
              let lastUpdateDate,
              now.timeIntervalSince(lastUpdateDate) >= segmentPauseThreshold else {
            return false
        }
        return !Self.looksLikeSameSegment(workingSegment, candidate)
    }

    private mutating func commitWorkingSegment() {
        let segment = Self.displayText(workingSegment)
        workingSegment = ""
        guard !segment.isEmpty else { return }
        let committed = Self.combinedText(segments: committedSegments, working: "")
        if Self.comparableText(committed) == Self.comparableText(segment)
            || Self.comparableText(committedSegments.last ?? "") == Self.comparableText(segment) {
            return
        }
        committedSegments.append(segment)
    }

    private static func combinedText(segments: [String], working: String) -> String {
        var parts = segments
        if !working.isEmpty {
            parts.append(working)
        }
        return displayText(parts.joined(separator: " "))
    }

    private static func looksLikeSameSegment(_ current: String, _ candidate: String) -> Bool {
        if equivalent(current, candidate) {
            return true
        }
        if current.hasPrefix(candidate) || candidate.hasPrefix(current) {
            return true
        }
        let shorterCount = min(current.count, candidate.count)
        guard shorterCount > 0 else { return false }
        let prefixCount = commonPrefixCount(current, candidate)
        if prefixCount >= min(4, shorterCount),
           Double(prefixCount) / Double(shorterCount) >= 0.55 {
            return true
        }
        let overlap = suffixPrefixOverlap(current, candidate)
        return overlap >= min(5, shorterCount)
            && Double(overlap) / Double(shorterCount) >= 0.45
    }

    private static func equivalent(_ lhs: String, _ rhs: String) -> Bool {
        displayText(lhs) == displayText(rhs)
    }

    private static func commonPrefixCount(_ lhs: String, _ rhs: String) -> Int {
        var count = 0
        var leftIndex = lhs.startIndex
        var rightIndex = rhs.startIndex
        while leftIndex < lhs.endIndex,
              rightIndex < rhs.endIndex,
              lhs[leftIndex] == rhs[rightIndex] {
            count += 1
            lhs.formIndex(after: &leftIndex)
            rhs.formIndex(after: &rightIndex)
        }
        return count
    }

    static func suffixPrefixOverlap(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let maxLength = min(left.count, right.count)
        for length in stride(from: maxLength, through: 1, by: -1) {
            if Array(left.suffix(length)) == Array(right.prefix(length)) {
                return length
            }
        }
        return 0
    }

    static func comparableText(_ text: String) -> String {
        displayText(text).unicodeScalars.reduce(into: "") { output, scalar in
            guard !CharacterSet.whitespacesAndNewlines.contains(scalar),
                  !CharacterSet.controlCharacters.contains(scalar),
                  !CharacterSet.punctuationCharacters.contains(scalar),
                  !CharacterSet.symbols.contains(scalar) else {
                return
            }
            output.unicodeScalars.append(scalar)
        }
    }
}

enum LiveASRFinalTextResolver {
    static func resolve(
        sessionResult: ASRRecognitionResult,
        snapshot: LiveASRTranscriptSnapshot
    ) -> ASRRecognitionResult {
        let text = resolvedText(
            sessionText: sessionResult.text,
            accumulatedText: snapshot.resolvedText
        )
        guard !text.isEmpty,
              text != LiveASRTranscriptAccumulator.displayText(sessionResult.text) else {
            return sessionResult
        }
        return ASRRecognitionResult(
            text: text,
            lowConfidenceSegments: sessionResult.lowConfidenceSegments,
            alternatives: sessionResult.alternatives,
            allowedAppleServerRecognition: sessionResult.allowedAppleServerRecognition
        )
    }

    static func resolvedText(sessionText: String, accumulatedText: String) -> String {
        let session = LiveASRTranscriptAccumulator.displayText(sessionText)
        let accumulated = LiveASRTranscriptAccumulator.displayText(accumulatedText)
        if session.isEmpty { return accumulated }
        if accumulated.isEmpty { return session }
        if session == accumulated { return session }

        let comparableSession = LiveASRTranscriptAccumulator.comparableText(session)
        let comparableAccumulated = LiveASRTranscriptAccumulator.comparableText(accumulated)
        if !comparableAccumulated.isEmpty,
           comparableSession.contains(comparableAccumulated) {
            return session
        }
        if !comparableSession.isEmpty,
           comparableAccumulated.contains(comparableSession) {
            return accumulated
        }

        let overlap = LiveASRTranscriptAccumulator.suffixPrefixOverlap(accumulated, session)
        if overlap > 0 {
            let suffix = String(session.dropFirst(overlap))
            return LiveASRTranscriptAccumulator.displayText(accumulated + suffix)
        }
        return LiveASRTranscriptAccumulator.displayText([accumulated, session].joined(separator: " "))
    }
}
