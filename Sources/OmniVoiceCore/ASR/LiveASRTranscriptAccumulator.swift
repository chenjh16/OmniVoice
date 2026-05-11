import Foundation

struct LiveASRTranscriptSnapshot: Equatable, Sendable {
    static let empty = LiveASRTranscriptSnapshot(displayText: "", resolvedText: "")

    let displayText: String
    let resolvedText: String

    var isEmpty: Bool {
        displayText.isEmpty && resolvedText.isEmpty
    }
}

enum LiveASRSegmentRelation: Equatable, Sendable {
    case duplicate
    case sameSegment
    case overlappingContinuation(overlap: Int)
    case unrelatedReset
}

struct LiveASRTranscriptAccumulator: Equatable, Sendable {
    static let defaultSegmentPauseThreshold: TimeInterval = 1.2

    private var committedDisplaySegments: [String] = []
    private var displayWorkingSegment = ""
    private var committedResolvedSegments: [String] = []
    private var resolvedWorkingSegment = ""
    private var lastUpdateDate: Date?
    private let segmentPauseThreshold: TimeInterval

    init(segmentPauseThreshold: TimeInterval = Self.defaultSegmentPauseThreshold) {
        self.segmentPauseThreshold = segmentPauseThreshold
    }

    mutating func reset() {
        committedDisplaySegments.removeAll(keepingCapacity: true)
        displayWorkingSegment = ""
        committedResolvedSegments.removeAll(keepingCapacity: true)
        resolvedWorkingSegment = ""
        lastUpdateDate = nil
    }

    mutating func accept(_ update: LiveASRUpdate, now: Date = Date()) -> LiveASRTranscriptSnapshot? {
        let text = Self.displayText(update.text)
        guard !text.isEmpty else { return nil }

        acceptDisplayText(text)
        acceptResolvedText(text)
        if update.isFinal {
            commitDisplayWorkingSegment()
            commitResolvedWorkingSegment()
        }
        lastUpdateDate = now
        return snapshot()
    }

    mutating func snapshotForFinal() -> LiveASRTranscriptSnapshot {
        commitDisplayWorkingSegment()
        commitResolvedWorkingSegment()
        return snapshot()
    }

    func snapshot() -> LiveASRTranscriptSnapshot {
        let display = Self.combinedText(segments: committedDisplaySegments, working: displayWorkingSegment)
        let resolved = Self.combinedText(segments: committedResolvedSegments, working: resolvedWorkingSegment)
        return LiveASRTranscriptSnapshot(displayText: display, resolvedText: resolved)
    }

    static func displayText(_ text: String) -> String {
        HUDLivePreviewPresentationPlanner.displayText(from: text)
    }

    private mutating func acceptDisplayText(_ text: String) {
        let candidate = candidateWithoutCommittedPrefix(text, committedSegments: committedDisplaySegments)
        guard !candidate.isEmpty else { return }

        switch Self.relation(current: displayWorkingSegment, candidate: candidate) {
        case .duplicate:
            return
        case .sameSegment:
            if candidate.count >= displayWorkingSegment.count {
                displayWorkingSegment = candidate
            }
        case let .overlappingContinuation(overlap):
            displayWorkingSegment = Self.mergedContinuation(
                current: displayWorkingSegment,
                candidate: candidate,
                overlap: overlap
            )
        case .unrelatedReset:
            commitDisplayWorkingSegment()
            let nextCandidate = candidateWithoutCommittedPrefix(text, committedSegments: committedDisplaySegments)
            if !nextCandidate.isEmpty {
                displayWorkingSegment = nextCandidate
            }
        }
    }

    private mutating func acceptResolvedText(_ text: String) {
        let candidate = candidateWithoutCommittedPrefix(text, committedSegments: committedResolvedSegments)
        guard !candidate.isEmpty else { return }

        switch Self.relation(current: resolvedWorkingSegment, candidate: candidate) {
        case .duplicate:
            return
        case .sameSegment:
            resolvedWorkingSegment = candidate
        case let .overlappingContinuation(overlap):
            resolvedWorkingSegment = Self.mergedContinuation(
                current: resolvedWorkingSegment,
                candidate: candidate,
                overlap: overlap
            )
        case .unrelatedReset:
            commitResolvedWorkingSegment()
            let nextCandidate = candidateWithoutCommittedPrefix(text, committedSegments: committedResolvedSegments)
            if !nextCandidate.isEmpty {
                resolvedWorkingSegment = nextCandidate
            }
        }
    }

    private func candidateWithoutCommittedPrefix(_ text: String, committedSegments: [String]) -> String {
        let committed = Self.combinedText(segments: committedSegments, working: "")
        guard !committed.isEmpty else { return text }
        if Self.equivalent(text, committed) {
            return ""
        }
        guard text.hasPrefix(committed) else { return text }
        let suffix = String(text.dropFirst(committed.count))
        return Self.displayText(suffix)
    }

    private mutating func commitDisplayWorkingSegment() {
        Self.commitWorkingSegment(
            committedSegments: &committedDisplaySegments,
            workingSegment: &displayWorkingSegment
        )
    }

    private mutating func commitResolvedWorkingSegment() {
        Self.commitWorkingSegment(
            committedSegments: &committedResolvedSegments,
            workingSegment: &resolvedWorkingSegment
        )
    }

    private static func commitWorkingSegment(committedSegments: inout [String], workingSegment: inout String) {
        let segment = displayText(workingSegment)
        workingSegment = ""
        guard !segment.isEmpty else { return }
        let committed = combinedText(segments: committedSegments, working: "")
        if comparableText(committed) == comparableText(segment)
            || comparableText(committedSegments.last ?? "") == comparableText(segment) {
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

    private static func relation(current: String, candidate: String) -> LiveASRSegmentRelation {
        guard !candidate.isEmpty else { return .duplicate }
        guard !current.isEmpty else { return .sameSegment }
        if equivalent(current, candidate) {
            return .duplicate
        }
        if current.hasPrefix(candidate) || candidate.hasPrefix(current) {
            return .sameSegment
        }

        let shorterCount = min(current.count, candidate.count)
        guard shorterCount > 0 else { return .unrelatedReset }
        let prefixCount = commonPrefixCount(current, candidate)
        if prefixCount >= min(4, shorterCount),
           Double(prefixCount) / Double(shorterCount) >= 0.55 {
            return .sameSegment
        }

        let overlap = suffixPrefixOverlap(current, candidate)
        if overlap >= 2,
           Double(overlap) / Double(shorterCount) >= 0.35 {
            return .overlappingContinuation(overlap: overlap)
        }
        if overlap >= min(5, shorterCount),
           Double(overlap) / Double(shorterCount) >= 0.45 {
            return .overlappingContinuation(overlap: overlap)
        }
        return .unrelatedReset
    }

    private static func mergedContinuation(current: String, candidate: String, overlap: Int) -> String {
        guard overlap > 0 else {
            return displayText([current, candidate].joined(separator: " "))
        }
        let suffix = String(candidate.dropFirst(overlap))
        return displayText(current + suffix)
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
