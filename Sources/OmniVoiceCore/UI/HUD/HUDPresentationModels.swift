import AppKit
import Foundation

public enum HUDLayoutMetrics {
    public static func clampedWidth(requestedWidth: CGFloat, screenWidth: CGFloat) -> CGFloat {
        min(max(requestedWidth, 168), min(screenWidth / 3, screenWidth - 40))
    }
}

public struct HUDLivePreviewPresentation: Equatable, Sendable {
    public let badge: String?
    public let text: String

    public init(badge: String?, text: String) {
        self.badge = badge
        self.text = text
    }
}

public enum HUDLivePreviewPresentationPlanner {
    public static func presentation(text: String, badge: String? = nil) -> HUDLivePreviewPresentation? {
        let trimmedText = displayText(from: text)
        let trimmedBadge = badge.flatMap { $0.nilIfBlank }
        guard !trimmedText.isEmpty else { return nil }
        return HUDLivePreviewPresentation(badge: trimmedBadge, text: trimmedText)
    }

    public static func displayText(from text: String) -> String {
        let sanitized = sanitizedPreviewText(from: text)
        let collapsed = sanitized
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return removingCJKBoundarySpaces(from: collapsed)
    }

    public static func sanitizedPreviewText(from text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var previousWasSpace = false

        for scalar in text.unicodeScalars {
            if shouldDrop(scalar) {
                continue
            }
            if shouldCollapseToSpace(scalar) {
                if !previousWasSpace {
                    result.append(" ")
                    previousWasSpace = true
                }
                continue
            }
            result.unicodeScalars.append(scalar)
            previousWasSpace = false
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldCollapseToSpace(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.whitespacesAndNewlines.contains(scalar)
            || CharacterSet.controlCharacters.contains(scalar)
            || scalar.value == 0x2028 // line separator
            || scalar.value == 0x2029 // paragraph separator
            || scalar.value == 0x0085 // next line
    }

    private static func shouldDrop(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x0000,
             0x200B...0x200F, // zero-width and bidirectional marks
             0x202A...0x202E, // bidirectional embedding/override controls
             0x2060...0x206F, // word joiner and directional formatting controls
             0xFEFF:
            return true
        default:
            return false
        }
    }

    private static func removingCJKBoundarySpaces(from text: String) -> String {
        let characters = Array(text)
        guard !characters.isEmpty else { return "" }
        var result = ""
        result.reserveCapacity(text.count)
        for index in characters.indices {
            let character = characters[index]
            if character == " ",
               index > characters.startIndex,
               index < characters.index(before: characters.endIndex),
               isCJKLike(characters[characters.index(before: index)]),
               isCJKLike(characters[characters.index(after: index)]) {
                continue
            }
            result.append(character)
        }
        return result
    }

    private static func isCJKLike(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3000...0x303F, // CJK symbols and punctuation
                 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0xFF00...0xFFEF,
                 0x20000...0x2A6DF,
                 0x2A700...0x2B73F,
                 0x2B740...0x2B81F,
                 0x2B820...0x2CEAF,
                 0x2F800...0x2FA1F:
                return true
            default:
                return false
            }
        }
    }
}

public enum TranscriptionHUDPresentationPolicy {
    public static func showsModelProgress(for mode: TranscriptionPipelineMode) -> Bool {
        mode != .systemASROnly
    }
}

public enum TranscriptionProgressNetworkPhaseCapPlanner {
    public static func cap(for phase: TranscriptionRequestPhase, hasReceivedDelta: Bool) -> Double {
        switch phase {
        case .preparingRequest:
            return hasReceivedDelta ? 0.95 : 0.20
        case .connecting:
            return hasReceivedDelta ? 0.95 : 0.36
        case .responseReceived:
            return hasReceivedDelta ? 0.95 : 0.56
        case .waitingForFirstDelta:
            return hasReceivedDelta ? 0.95 : 0.72
        case .streaming:
            return 0.95
        case .completed:
            return 1
        }
    }
}

public enum HUDDraftBadgeMetrics {
    public static let height: CGFloat = 17
    public static let horizontalPadding: CGFloat = 7
    public static let minWidth: CGFloat = 34
    public static let fontSize: CGFloat = 10.5

    public static func width(for text: String, font: NSFont = .systemFont(ofSize: fontSize, weight: .semibold)) -> CGFloat {
        let measured = (text as NSString).size(withAttributes: [.font: font]).width
        return max(minWidth, ceil(measured + horizontalPadding * 2))
    }
}

public enum HUDLivePreviewLayoutMetrics {
    public static let horizontalInset: CGFloat = 17
    public static let waveformWidth: CGFloat = 34
    public static let waveformTextSpacing: CGFloat = 9
    public static let badgeTextSpacing: CGFloat = 6
    public static let minTextWidth: CGFloat = 72
    public static let textHeight: CGFloat = 18
    public static let fadeWidth: CGFloat = 100
}

public struct HUDLivePreviewLayout: Equatable, Sendable {
    public let hudWidth: CGFloat
    public let textViewportWidth: CGFloat
    public let fixedAccessoryWidth: CGFloat
    public let fadeTailEnabled: Bool
}

public enum HUDLivePreviewLayoutPlanner {
    public static func layout(
        measuredTextWidth: CGFloat,
        measuredBadgeWidth: CGFloat,
        includesWaveform: Bool,
        screenWidth: CGFloat
    ) -> HUDLivePreviewLayout {
        let badgeWidth = measuredBadgeWidth > 0 ? measuredBadgeWidth : 0
        let badgeSpacing = badgeWidth > 0 ? HUDLivePreviewLayoutMetrics.badgeTextSpacing : 0
        let waveformWidth = includesWaveform
            ? HUDLivePreviewLayoutMetrics.waveformWidth + HUDLivePreviewLayoutMetrics.waveformTextSpacing
            : 0
        let fixedAccessoryWidth = HUDLivePreviewLayoutMetrics.horizontalInset * 2
            + waveformWidth
            + badgeWidth
            + badgeSpacing
        let requestedTextWidth = max(HUDLivePreviewLayoutMetrics.minTextWidth, ceil(measuredTextWidth))
        let requestedHUDWidth = fixedAccessoryWidth + requestedTextWidth
        let hudWidth = HUDLayoutMetrics.clampedWidth(requestedWidth: requestedHUDWidth, screenWidth: screenWidth)
        let textViewportWidth = max(
            HUDLivePreviewLayoutMetrics.minTextWidth,
            floor(hudWidth - fixedAccessoryWidth)
        )
        return HUDLivePreviewLayout(
            hudWidth: hudWidth,
            textViewportWidth: textViewportWidth,
            fixedAccessoryWidth: fixedAccessoryWidth,
            fadeTailEnabled: measuredTextWidth > textViewportWidth + 1
        )
    }
}

public struct HUDLivePreviewSessionLayoutState: Equatable, Sendable {
    public static let empty = HUDLivePreviewSessionLayoutState()

    public let maxHUDWidth: CGFloat
    public let maxTextViewportWidth: CGFloat

    public init(maxHUDWidth: CGFloat = 0, maxTextViewportWidth: CGFloat = 0) {
        self.maxHUDWidth = maxHUDWidth
        self.maxTextViewportWidth = maxTextViewportWidth
    }
}

public struct HUDLivePreviewSessionLayout: Equatable, Sendable {
    public let layout: HUDLivePreviewLayout
    public let state: HUDLivePreviewSessionLayoutState
}

public enum HUDLivePreviewSessionLayoutPlanner {
    public static func layout(
        rawLayout: HUDLivePreviewLayout,
        previous state: HUDLivePreviewSessionLayoutState
    ) -> HUDLivePreviewSessionLayout {
        let nextState = HUDLivePreviewSessionLayoutState(
            maxHUDWidth: max(state.maxHUDWidth, rawLayout.hudWidth),
            maxTextViewportWidth: max(state.maxTextViewportWidth, rawLayout.textViewportWidth)
        )
        let stableLayout = HUDLivePreviewLayout(
            hudWidth: nextState.maxHUDWidth,
            textViewportWidth: nextState.maxTextViewportWidth,
            fixedAccessoryWidth: rawLayout.fixedAccessoryWidth,
            fadeTailEnabled: rawLayout.fadeTailEnabled
        )
        return HUDLivePreviewSessionLayout(layout: stableLayout, state: nextState)
    }
}
