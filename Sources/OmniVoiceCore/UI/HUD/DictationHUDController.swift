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
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBadge = badge.flatMap { $0.nilIfBlank }
        guard !trimmedText.isEmpty else { return nil }
        return HUDLivePreviewPresentation(badge: trimmedBadge, text: trimmedText)
    }
}

public enum TranscriptionHUDPresentationPolicy {
    public static func showsModelProgress(for mode: TranscriptionPipelineMode) -> Bool {
        mode != .systemASROnly
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

@MainActor
public final class DictationHUDController {
    private let panel: NSPanel
    private let capsuleView = CapsuleBackgroundView()
    private let waveformView = WaveformView()
    private let label = NSTextField(labelWithString: "")
    private let previewStack = NSStackView()
    private let previewBadge = DraftBadgeView()
    private let previewLabel = NSTextField(labelWithString: "")
    private let progress = ProgressBarView()
    private let contentStack = NSStackView()
    private let textStack = NSStackView()
    private var progressTimer: Timer?
    private var hideWorkItem: DispatchWorkItem?
    private var transcribingStartDate: Date?
    private var estimator: TranscriptionProgressEstimator?
    private var receivedDelta = false
    private var streamedText = ""
    private var deltaChunkCount = 0
    private var visualStyle: HUDVisualStyle = .automatic
    private var surfaceGeneration = 0

    public init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 210, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true

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

        previewLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        previewLabel.alignment = .left
        previewLabel.lineBreakMode = .byTruncatingMiddle
        previewLabel.maximumNumberOfLines = 1
        previewLabel.translatesAutoresizingMaskIntoConstraints = false
        previewLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        previewStack.orientation = .horizontal
        previewStack.alignment = .centerY
        previewStack.spacing = 6
        previewStack.translatesAutoresizingMaskIntoConstraints = false
        previewStack.isHidden = true
        previewStack.addArrangedSubview(previewBadge)
        previewStack.addArrangedSubview(previewLabel)

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
        panel.contentView?.addSubview(capsuleView)
        capsuleView.addSubview(contentStack)
        capsuleView.onEffectiveAppearanceChanged = { [weak self] in
            self?.applyVisualStyle()
        }

        NSLayoutConstraint.activate([
            capsuleView.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            capsuleView.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            capsuleView.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            capsuleView.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor),

            contentStack.centerXAnchor.constraint(equalTo: capsuleView.centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: capsuleView.centerYAnchor),
            contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: capsuleView.leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(lessThanOrEqualTo: capsuleView.trailingAnchor, constant: -14),

            waveformView.widthAnchor.constraint(equalToConstant: 34),
            waveformView.heightAnchor.constraint(equalToConstant: 18),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 88),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            previewBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: HUDDraftBadgeMetrics.minWidth),
            previewBadge.heightAnchor.constraint(equalToConstant: HUDDraftBadgeMetrics.height),
            previewLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            previewLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            previewStack.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
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
        label.isHidden = false
        previewStack.isHidden = true
        previewBadge.text = ""
        previewLabel.stringValue = ""
        label.stringValue = text
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
        previewLabel.stringValue = tailPreview(presentation.text)
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
        waveformView.isHidden = true
        waveformView.stopAnimating()
        progress.isHidden = !showsProgress
        progress.progress = 0
        label.isHidden = false
        previewStack.isHidden = true
        label.stringValue = text
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
        label.stringValue = tailPreview(streamedText)
        updateWidthForCurrentText()
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
        label.isHidden = false
        previewStack.isHidden = true
        label.stringValue = message
        show(width: width(for: message, includesWaveform: false), spring: false)
        scheduleHide(after: duration)
    }

    public func completeAndHide() {
        progress.progress = 1
        scheduleHide(after: 0.22)
    }

    public func frameForMorphAndHide() -> NSRect? {
        let frame = currentFrame
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
        let frame = NSRect(
            x: screenFrame.midX - clampedWidth / 2,
            y: screenFrame.minY + 18,
            width: clampedWidth,
            height: 40
        )
        panel.setFrame(frame, display: true, animate: panel.isVisible)
        panel.contentView?.layoutSubtreeIfNeeded()
        if panel.frame.minY < screenFrame.minY + 8 {
            panel.setFrameOrigin(NSPoint(x: panel.frame.minX, y: screenFrame.minY + 18))
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
        progress.progress = min(max(value, 0), receivedDelta ? 0.95 : 0.90)
    }

    private func updateWidthForCurrentText() {
        if !previewStack.isHidden {
            placePanel(width: widthForPreview(
                text: previewLabel.stringValue,
                badge: previewBadge.text,
                includesWaveform: !waveformView.isHidden
            ))
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

    private func widthForPreview(text: String, badge: String, includesWaveform: Bool) -> CGFloat {
        let textFont = previewLabel.font ?? .systemFont(ofSize: 12.5, weight: .semibold)
        let measuredText = (text as NSString).size(withAttributes: [.font: textFont]).width
        let measuredBadge = badge.isEmpty ? 0 : HUDDraftBadgeMetrics.width(for: badge)
        let badgeSpacing = badge.isEmpty ? 0 : previewStack.spacing
        let accessoryWidth: CGFloat = includesWaveform ? 34 + contentStack.spacing : 0
        return measuredText + measuredBadge + badgeSpacing + accessoryWidth + 34
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
        streamedText = ""
        deltaChunkCount = 0
        label.isHidden = false
        previewStack.isHidden = true
        previewBadge.text = ""
        previewLabel.stringValue = ""
    }

    private func applyVisualStyle() {
        let resolved = HUDSurfaceResolver.resolve(
            preference: visualStyle,
            systemAppearance: glassAppearance(for: capsuleView.effectiveAppearance)
        )
        capsuleView.surface = resolved
        applyPalette()
    }

    private func applyPalette() {
        let tone: HUDStatusTone = capsuleView.statusStyle == .warning ? .warning : .normal
        if capsuleView.surface == .nativeGlass {
            let readability = GlassReadabilityResolver.resolve(
                appearance: glassAppearance(for: capsuleView.effectiveAppearance),
                status: tone
            )
            capsuleView.glassReadability = readability
            applyTextTone(readability.textTone, shadowAlpha: readability.shadowAlpha)
            progress.palette = readability.textTone == .light
                ? .light(warning: readability.warning)
                : .dark(warning: readability.warning)
            waveformView.palette = readability.textTone == .light ? .light : .dark
            return
        }
        let palette = HUDPaletteResolver.resolve(surface: capsuleView.surface, status: tone)
        applyTextTone(palette.textTone, shadowAlpha: 0)
        progress.palette = palette.textTone == .light
            ? .light(warning: palette.warning)
            : .dark(warning: palette.warning)
        waveformView.palette = palette.textTone == .light ? .light : .dark
    }

    private func applyTextTone(_ tone: HUDTextTone, shadowAlpha: CGFloat) {
        switch tone {
        case .light:
            label.textColor = NSColor.white.withAlphaComponent(0.96)
            previewLabel.textColor = NSColor.white.withAlphaComponent(0.92)
            previewBadge.textColor = NSColor.white.withAlphaComponent(0.96)
            previewBadge.fillColor = NSColor.white.withAlphaComponent(0.16)
            previewBadge.borderColor = NSColor.white.withAlphaComponent(0.20)
        case .dark:
            label.textColor = NSColor(calibratedWhite: 0.08, alpha: 0.96)
            previewLabel.textColor = NSColor(calibratedWhite: 0.08, alpha: 0.90)
            previewBadge.textColor = NSColor(calibratedWhite: 0.08, alpha: 0.96)
            previewBadge.fillColor = NSColor.black.withAlphaComponent(0.08)
            previewBadge.borderColor = NSColor.black.withAlphaComponent(0.12)
        }
        previewBadge.borderWidth = 0.6
        label.shadow = shadow(alpha: shadowAlpha)
        previewLabel.shadow = shadow(alpha: shadowAlpha)
        previewBadge.shadow = shadow(alpha: shadowAlpha)
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
