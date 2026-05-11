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

@MainActor
public final class DictationHUDController {
    private let panel: NSPanel
    private let shadowView = SurfaceShadowView(role: .hud)
    private let capsuleView = CapsuleBackgroundView()
    private let waveformView = WaveformView()
    private let label = HaloTextField(labelWithString: "")
    private let previewStack = NSStackView()
    private let previewBadge = DraftBadgeView()
    private let previewTextView = LivePreviewTextView()
    private let progress = ProgressBarView()
    private let contentStack = NSStackView()
    private let textStack = NSStackView()
    private var contentStackCenterXConstraint: NSLayoutConstraint!
    private var contentStackPreviewLeadingConstraint: NSLayoutConstraint!
    private var previewTextWidthConstraint: NSLayoutConstraint!
    private var progressTimer: Timer?
    private var hideWorkItem: DispatchWorkItem?
    private var transcribingStartDate: Date?
    private var estimator: TranscriptionProgressEstimator?
    private var receivedDelta = false
    private var requestPhase: TranscriptionRequestPhase = .preparingRequest
    private var streamedText = ""
    private var deltaChunkCount = 0
    private var visualStyle: HUDVisualStyle = .automatic
    private var primaryTextColor = NSColor.white.withAlphaComponent(0.96)
    private var surfaceGeneration = 0
    private var previewLayoutState = HUDLivePreviewSessionLayoutState.empty

    public init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 210, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = HUDSurfaceMetrics.usesSystemShadow
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true

        shadowView.translatesAutoresizingMaskIntoConstraints = false
        capsuleView.translatesAutoresizingMaskIntoConstraints = false

        label.font = .systemFont(ofSize: 12.5, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.96)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false

        previewBadge.translatesAutoresizingMaskIntoConstraints = false
        previewBadge.setContentHuggingPriority(.required, for: .horizontal)
        previewBadge.setContentCompressionResistancePriority(.required, for: .horizontal)

        previewTextView.font = .systemFont(ofSize: 12.5, weight: .semibold)
        previewTextView.translatesAutoresizingMaskIntoConstraints = false
        previewTextView.setContentCompressionResistancePriority(.required, for: .horizontal)

        previewStack.orientation = .horizontal
        previewStack.alignment = .centerY
        previewStack.spacing = HUDLivePreviewLayoutMetrics.badgeTextSpacing
        previewStack.translatesAutoresizingMaskIntoConstraints = false
        previewStack.isHidden = true
        previewStack.addArrangedSubview(previewBadge)
        previewStack.addArrangedSubview(previewTextView)

        waveformView.translatesAutoresizingMaskIntoConstraints = false

        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.isHidden = true

        textStack.orientation = .vertical
        textStack.alignment = .centerX
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(label)
        textStack.addArrangedSubview(previewStack)
        textStack.addArrangedSubview(progress)

        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 9
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(waveformView)
        contentStack.addArrangedSubview(textStack)

        panel.contentView = NSView()
        panel.contentView?.addSubview(shadowView)
        panel.contentView?.addSubview(capsuleView)
        capsuleView.addSubview(contentStack)
        capsuleView.onEffectiveAppearanceChanged = { [weak self] in
            self?.applyVisualStyle()
        }
        contentStackCenterXConstraint = contentStack.centerXAnchor.constraint(equalTo: capsuleView.centerXAnchor)
        contentStackPreviewLeadingConstraint = contentStack.leadingAnchor.constraint(
            equalTo: capsuleView.leadingAnchor,
            constant: HUDLivePreviewLayoutMetrics.horizontalInset
        )
        contentStackPreviewLeadingConstraint.isActive = false
        previewTextWidthConstraint = previewTextView.widthAnchor.constraint(
            equalToConstant: HUDLivePreviewLayoutMetrics.minTextWidth
        )

        NSLayoutConstraint.activate([
            shadowView.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            shadowView.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            shadowView.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            shadowView.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor),

            capsuleView.leadingAnchor.constraint(
                equalTo: panel.contentView!.leadingAnchor,
                constant: SurfaceDepthMetrics.hudInsets.left
            ),
            capsuleView.trailingAnchor.constraint(
                equalTo: panel.contentView!.trailingAnchor,
                constant: -SurfaceDepthMetrics.hudInsets.right
            ),
            capsuleView.topAnchor.constraint(
                equalTo: panel.contentView!.topAnchor,
                constant: SurfaceDepthMetrics.hudInsets.top
            ),
            capsuleView.bottomAnchor.constraint(
                equalTo: panel.contentView!.bottomAnchor,
                constant: -SurfaceDepthMetrics.hudInsets.bottom
            ),

            contentStackCenterXConstraint,
            contentStack.centerYAnchor.constraint(equalTo: capsuleView.centerYAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: capsuleView.leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: capsuleView.trailingAnchor, constant: -14),

            waveformView.widthAnchor.constraint(equalToConstant: 34),
            waveformView.heightAnchor.constraint(equalToConstant: 18),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 88),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            previewBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: HUDDraftBadgeMetrics.minWidth),
            previewBadge.heightAnchor.constraint(equalToConstant: HUDDraftBadgeMetrics.height),
            previewTextWidthConstraint,
            previewTextView.heightAnchor.constraint(equalToConstant: HUDLivePreviewLayoutMetrics.textHeight),
            progress.widthAnchor.constraint(equalTo: label.widthAnchor),
            progress.heightAnchor.constraint(equalToConstant: 3)
        ])
        applyVisualStyle()
    }

    public var currentFrame: NSRect? {
        panel.isVisible ? panel.frame : nil
    }

    public var diagnosticSnapshot: SurfaceDiagnosticSnapshot {
        SurfaceDiagnosticSnapshot(
            panelType: "nonactivating_hud",
            levelName: "statusBar",
            isVisible: panel.isVisible,
            frame: panel.isVisible ? panel.frame.cgRectValue : nil,
            windowNumber: panel.isVisible ? panel.windowNumber : nil
        )
    }

    public func renderedPNGData() -> Data? {
        guard panel.isVisible, let contentView = panel.contentView else { return nil }
        return contentView.omniVoiceRenderedPNGData()
    }

    public func setVisualStyle(_ style: HUDVisualStyle) {
        visualStyle = style
        applyVisualStyle()
    }

    public func showListening(text: String = "正在聆听") {
        resetTranscriptionState()
        prepareCompactSurface()
        capsuleView.statusStyle = .normal
        applyPalette()
        waveformView.isHidden = false
        waveformView.startAnimating()
        progress.isHidden = true
        useCenteredContentLayout()
        label.isHidden = false
        previewStack.isHidden = true
        previewBadge.text = ""
        previewTextView.text = ""
        setLabelText(text)
        waveformView.level = 0.08
        show(width: width(for: text, includesWaveform: true), spring: true)
    }

    public func updateRMSLevel(_ level: Float) {
        waveformView.level = CGFloat(level)
    }

    public func updateListeningPreview(_ text: String, badge: String? = nil) {
        guard !waveformView.isHidden, progress.isHidden else { return }
        guard let presentation = HUDLivePreviewPresentationPlanner.presentation(text: text, badge: badge) else { return }
        label.isHidden = true
        previewStack.isHidden = false
        previewBadge.isHidden = presentation.badge == nil
        previewBadge.text = presentation.badge ?? ""
        previewTextView.text = presentation.text
        usePreviewContentLayout()
        updateWidthForCurrentText()
    }

    public func showTranscribing(recordingSeconds: Double, text: String = "正在转写", showsProgress: Bool = true) {
        resetTranscriptionState()
        prepareCompactSurface()
        capsuleView.statusStyle = .normal
        applyPalette()
        if showsProgress {
            estimator = TranscriptionProgressEstimator(recordingSeconds: recordingSeconds)
            transcribingStartDate = Date()
        }
        requestPhase = .preparingRequest
        useCenteredContentLayout()
        waveformView.isHidden = true
        waveformView.stopAnimating()
        progress.isHidden = !showsProgress
        progress.requestPhase = .preparingRequest
        progress.progress = 0
        label.isHidden = false
        previewStack.isHidden = true
        setLabelText(text)
        show(width: width(for: text, includesWaveform: false), spring: false)
        if showsProgress {
            progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tickProgress() }
            }
        }
    }

    public func appendTranscriptionDelta(_ delta: String) {
        receivedDelta = true
        deltaChunkCount += 1
        streamedText += delta
        setLabelText(tailPreview(streamedText))
        updateWidthForCurrentText()
    }

    public func updateTranscriptionRequestPhase(_ phase: TranscriptionRequestPhase) {
        guard !progress.isHidden else { return }
        requestPhase = phase
        progress.requestPhase = phase
        if phase == .completed {
            progress.progress = max(progress.progress, 0.98)
        }
    }

    public func showTransientStatus(_ message: String, duration: TimeInterval = 1.2) {
        showStatus(message, duration: duration, style: .normal)
    }

    public func showWarningStatus(_ message: String, duration: TimeInterval = 3.0) {
        showStatus(message, duration: duration, style: .warning)
    }

    private func showStatus(_ message: String, duration: TimeInterval, style: CapsuleBackgroundView.Style) {
        resetTranscriptionState()
        prepareCompactSurface()
        capsuleView.statusStyle = style
        applyPalette()
        waveformView.isHidden = true
        waveformView.stopAnimating()
        progress.isHidden = true
        useCenteredContentLayout()
        label.isHidden = false
        previewStack.isHidden = true
        setLabelText(message)
        show(width: width(for: message, includesWaveform: false), spring: false)
        scheduleHide(after: duration)
    }

    public func completeAndHide() {
        progress.progress = 1
        scheduleHide(after: 0.22)
    }

    public func frameForMorphAndHide() -> NSRect? {
        let frame = panel.isVisible
            ? NSRect(SurfaceDepthMetrics.visualFrame(forWindowFrame: panel.frame.cgRectValue, role: .hud))
            : nil
        hide()
        return frame
    }

    public func hide() {
        surfaceGeneration += 1
        resetTranscriptionState()
        guard panel.isVisible else { return }
        panel.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
            panel.contentView?.animator().layer?.setAffineTransform(CGAffineTransform(scaleX: 0.97, y: 0.97))
        } completionHandler: { [panel] in
            panel.orderOut(nil)
            panel.alphaValue = 1
            panel.contentView?.layer?.setAffineTransform(.identity)
        }
    }

    private func show(width: CGFloat, spring: Bool) {
        surfaceGeneration += 1
        panel.ignoresMouseEvents = true
        capsuleView.cornerRadiusOverride = nil
        shadowView.cornerRadius = 0
        placePanel(width: width)
        panel.contentView?.wantsLayer = true
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.alphaValue = 1
        panel.contentView?.layer?.setAffineTransform(.identity)
        if !panel.isVisible {
            panel.contentView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.96, y: 0.96))
            panel.orderFrontRegardless()
        } else {
            panel.orderFrontRegardless()
        }
        panel.displayIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = spring ? 0.28 : 0.20
            context.timingFunction = CAMediaTimingFunction(name: spring ? .easeOut : .easeInEaseOut)
            panel.animator().alphaValue = 1
            panel.contentView?.animator().layer?.setAffineTransform(.identity)
        }
    }

    private func placePanel(width: CGFloat) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let clampedWidth = HUDLayoutMetrics.clampedWidth(requestedWidth: width, screenWidth: screenFrame.width)
        let windowSize = SurfaceDepthMetrics.windowSize(
            forVisualSize: CGSize(width: clampedWidth, height: 40),
            role: .hud
        )
        let frame = NSRect(
            x: screenFrame.midX - windowSize.width / 2,
            y: screenFrame.minY + 18 - SurfaceDepthMetrics.hudInsets.bottom,
            width: windowSize.width,
            height: windowSize.height
        )
        panel.setFrame(frame, display: true, animate: panel.isVisible)
        panel.contentView?.layoutSubtreeIfNeeded()
        if panel.frame.minY < screenFrame.minY + 2 {
            panel.setFrameOrigin(NSPoint(
                x: panel.frame.minX,
                y: screenFrame.minY + 18 - SurfaceDepthMetrics.hudInsets.bottom
            ))
        }
    }

    private func prepareCompactSurface() {
        surfaceGeneration += 1
        hideWorkItem?.cancel()
        hideWorkItem = nil
        contentStack.isHidden = false
        contentStack.alphaValue = 1
    }

    private func scheduleHide(after duration: TimeInterval) {
        hideWorkItem?.cancel()
        let generation = surfaceGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.surfaceGeneration == generation else { return }
            self.hide()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func tickProgress() {
        guard let start = transcribingStartDate, let estimator else { return }
        let elapsed = Date().timeIntervalSince(start)
        var value = estimator.progress(
            elapsedSeconds: elapsed,
            hasReceivedDelta: receivedDelta,
            isFinished: false,
            deltaChunkCount: deltaChunkCount,
            deltaCharacterCount: streamedText.count
        )
        if !receivedDelta && elapsed > 4 {
            value += sin(elapsed * 4) * 0.006
        }
        progress.activityPhase = CGFloat(elapsed)
        let cap = TranscriptionProgressNetworkPhaseCapPlanner.cap(
            for: requestPhase,
            hasReceivedDelta: receivedDelta
        )
        progress.progress = min(max(value, 0), cap)
    }

    private func updateWidthForCurrentText() {
        if !previewStack.isHidden {
            let rawLayout = previewLayout(
                text: previewTextView.text,
                badge: previewBadge.isHidden ? "" : previewBadge.text,
                includesWaveform: !waveformView.isHidden
            )
            let plannedLayout = HUDLivePreviewSessionLayoutPlanner.layout(
                rawLayout: rawLayout,
                previous: previewLayoutState
            )
            previewLayoutState = plannedLayout.state
            let layout = plannedLayout.layout
            previewTextWidthConstraint.constant = layout.textViewportWidth
            previewTextView.fadeTailEnabled = layout.fadeTailEnabled
            previewTextView.fadeWidth = HUDLivePreviewLayoutMetrics.fadeWidth
            placePanel(width: layout.hudWidth)
        } else {
            placePanel(width: width(for: label.stringValue, includesWaveform: !waveformView.isHidden))
        }
    }

    private func width(for text: String, includesWaveform: Bool) -> CGFloat {
        let font = label.font ?? .systemFont(ofSize: 12.5, weight: .semibold)
        let measuredText = (text as NSString).size(withAttributes: [.font: font]).width
        let accessoryWidth: CGFloat = includesWaveform ? 34 + contentStack.spacing : 0
        return measuredText + accessoryWidth + 34
    }

    private func previewLayout(text: String, badge: String, includesWaveform: Bool) -> HUDLivePreviewLayout {
        let textFont = previewTextView.font
        let measuredText = (text as NSString).size(withAttributes: [.font: textFont]).width
        let measuredBadge = badge.isEmpty ? 0 : HUDDraftBadgeMetrics.width(for: badge)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        return HUDLivePreviewLayoutPlanner.layout(
            measuredTextWidth: measuredText,
            measuredBadgeWidth: measuredBadge,
            includesWaveform: includesWaveform,
            screenWidth: screenFrame.width
        )
    }

    private func tailPreview(_ text: String) -> String {
        guard text.count > 44 else { return text }
        return "…" + text.suffix(44)
    }

    private func resetTranscriptionState() {
        progressTimer?.invalidate()
        progressTimer = nil
        waveformView.stopAnimating()
        transcribingStartDate = nil
        estimator = nil
        receivedDelta = false
        requestPhase = .preparingRequest
        progress.requestPhase = .preparingRequest
        streamedText = ""
        deltaChunkCount = 0
        label.isHidden = false
        previewStack.isHidden = true
        previewBadge.text = ""
        previewTextView.text = ""
        previewLayoutState = .empty
        useCenteredContentLayout()
    }

    private func applyVisualStyle() {
        let resolved = HUDSurfaceResolver.resolve(
            preference: visualStyle,
            systemAppearance: glassAppearance(for: capsuleView.effectiveAppearance)
        )
        capsuleView.surface = resolved
        shadowView.surface = resolved
        applyPalette()
    }

    private func applyPalette() {
        let tone: HUDStatusTone = capsuleView.statusStyle == .warning ? .warning : .normal
        shadowView.status = tone
        if capsuleView.surface == .nativeGlass {
            let readability = GlassReadabilityResolver.resolve(
                appearance: glassAppearance(for: capsuleView.effectiveAppearance),
                status: tone
            )
            capsuleView.glassReadability = readability
            applyTextTone(
                readability.textTone,
                shadowAlpha: readability.shadowAlpha,
                haloAlpha: readability.haloAlpha,
                haloWidth: readability.haloWidth
            )
            progress.palette = readability.textTone == .light
                ? .light(warning: readability.warning)
                : .dark(warning: readability.warning)
            waveformView.palette = readability.textTone == .light ? .light : .dark
            return
        }
        let palette = HUDPaletteResolver.resolve(surface: capsuleView.surface, status: tone)
        applyTextTone(palette.textTone, shadowAlpha: 0, haloAlpha: 0, haloWidth: 0)
        progress.palette = palette.textTone == .light
            ? .light(warning: palette.warning)
            : .dark(warning: palette.warning)
        waveformView.palette = palette.textTone == .light ? .light : .dark
    }

    private func applyTextTone(
        _ tone: HUDTextTone,
        shadowAlpha: CGFloat,
        haloAlpha: CGFloat,
        haloWidth: CGFloat
    ) {
        switch tone {
        case .light:
            primaryTextColor = NSColor.white.withAlphaComponent(0.96)
            previewTextView.textColor = NSColor.white.withAlphaComponent(0.92)
            previewBadge.textColor = NSColor.white.withAlphaComponent(0.96)
            previewBadge.fillColor = NSColor.white.withAlphaComponent(0.16)
            previewBadge.borderColor = NSColor.white.withAlphaComponent(0.20)
        case .dark:
            primaryTextColor = NSColor(calibratedWhite: 0.08, alpha: 0.96)
            previewTextView.textColor = NSColor(calibratedWhite: 0.08, alpha: 0.90)
            previewBadge.textColor = NSColor(calibratedWhite: 0.08, alpha: 0.96)
            previewBadge.fillColor = NSColor.black.withAlphaComponent(0.08)
            previewBadge.borderColor = NSColor.black.withAlphaComponent(0.12)
        }
        label.textColor = primaryTextColor
        let haloColor = textHaloColor(for: tone, alpha: haloAlpha)
        label.textHaloColor = haloColor
        label.textHaloWidth = haloWidth
        label.needsDisplay = true
        previewTextView.textHaloColor = haloColor
        previewTextView.textHaloWidth = haloWidth
        previewBadge.textHaloColor = textHaloColor(for: tone, alpha: haloAlpha * 0.82)
        previewBadge.textHaloWidth = haloWidth * 0.86
        previewBadge.borderWidth = 0.6
        label.shadow = shadow(alpha: shadowAlpha)
        previewTextView.shadow = shadow(alpha: shadowAlpha)
        previewBadge.shadow = shadow(alpha: shadowAlpha)
    }

    private func setLabelText(_ text: String) {
        label.stringValue = text
        label.needsDisplay = true
    }

    private func usePreviewContentLayout() {
        if contentStackCenterXConstraint.isActive {
            contentStackCenterXConstraint.isActive = false
        }
        if !contentStackPreviewLeadingConstraint.isActive {
            contentStackPreviewLeadingConstraint.isActive = true
        }
    }

    private func useCenteredContentLayout() {
        if contentStackPreviewLeadingConstraint.isActive {
            contentStackPreviewLeadingConstraint.isActive = false
        }
        if !contentStackCenterXConstraint.isActive {
            contentStackCenterXConstraint.isActive = true
        }
    }
}

private func shadow(alpha: CGFloat) -> NSShadow? {
    guard alpha > 0 else { return nil }
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
    shadow.shadowBlurRadius = 4
    shadow.shadowOffset = NSSize(width: 0, height: -0.5)
    return shadow
}
