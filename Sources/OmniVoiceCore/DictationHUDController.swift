import AppKit
import Foundation

public enum HUDLayoutMetrics {
    public static func clampedWidth(requestedWidth: CGFloat, screenWidth: CGFloat) -> CGFloat {
        min(max(requestedWidth, 168), min(screenWidth / 3, screenWidth - 40))
    }
}

@MainActor
public final class DictationHUDController {
    private let panel: NSPanel
    private let capsuleView = CapsuleBackgroundView()
    private let waveformView = WaveformView()
    private let label = NSTextField(labelWithString: "")
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

        waveformView.translatesAutoresizingMaskIntoConstraints = false

        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.isHidden = true

        textStack.orientation = .vertical
        textStack.alignment = .centerX
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.addArrangedSubview(label)
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
        label.stringValue = text
        waveformView.level = 0.08
        show(width: width(for: text, includesWaveform: true), spring: true)
    }

    public func updateRMSLevel(_ level: Float) {
        waveformView.level = CGFloat(level)
    }

    public func showTranscribing(recordingSeconds: Double, text: String = "正在转写") {
        resetTranscriptionState()
        prepareCompactSurface()
        capsuleView.statusStyle = .normal
        applyPalette()
        estimator = TranscriptionProgressEstimator(recordingSeconds: recordingSeconds)
        transcribingStartDate = Date()
        waveformView.isHidden = true
        waveformView.stopAnimating()
        progress.isHidden = false
        progress.progress = 0
        label.stringValue = text
        show(width: width(for: text, includesWaveform: false), spring: false)
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickProgress() }
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
        placePanel(width: width(for: label.stringValue, includesWaveform: false))
    }

    private func width(for text: String, includesWaveform: Bool) -> CGFloat {
        let font = label.font ?? .systemFont(ofSize: 12.5, weight: .semibold)
        let measuredText = (text as NSString).size(withAttributes: [.font: font]).width
        let accessoryWidth: CGFloat = includesWaveform ? 34 + contentStack.spacing : 0
        return measuredText + accessoryWidth + 34
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
        case .dark:
            label.textColor = NSColor(calibratedWhite: 0.08, alpha: 0.96)
        }
        label.shadow = shadow(alpha: shadowAlpha)
    }
}

private final class CapsuleBackgroundView: NSView {
    enum Style {
        case normal
        case warning
    }

    var statusStyle: Style = .normal {
        didSet {
            updateNativeGlassAppearance()
            needsDisplay = true
        }
    }

    var surface: HUDResolvedSurface = .darkCapsule {
        didSet { configureNativeGlassIfNeeded() }
    }

    var cornerRadiusOverride: CGFloat? {
        didSet {
            updateNativeGlassCornerRadius()
            needsDisplay = true
        }
    }

    private var nativeGlassView: NSView?
    var onEffectiveAppearanceChanged: (() -> Void)?
    var glassReadability = GlassReadabilityResolver.resolve(appearance: .light, status: .normal) {
        didSet {
            updateNativeGlassAppearance()
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    private var currentCornerRadius: CGFloat {
        min(cornerRadiusOverride ?? bounds.height / 2, min(bounds.width, bounds.height) / 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = currentCornerRadius
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        switch (surface, statusStyle) {
        case (.darkCapsule, .normal):
            NSColor(calibratedRed: 0.035, green: 0.039, blue: 0.047, alpha: 0.97).setFill()
            path.fill()
        case (.darkCapsule, .warning):
            NSColor(calibratedRed: 0.240, green: 0.115, blue: 0.055, alpha: 0.98).setFill()
            path.fill()
        case (.lightCapsule, .normal):
            NSColor(calibratedRed: 0.985, green: 0.977, blue: 0.948, alpha: 0.98).setFill()
            path.fill()
        case (.lightCapsule, .warning):
            NSColor(calibratedRed: 1.0, green: 0.895, blue: 0.770, alpha: 0.98).setFill()
            path.fill()
        case (.fallbackGlass, .normal):
            NSColor(calibratedWhite: 1.0, alpha: 0.46).setFill()
            path.fill()
        case (.fallbackGlass, .warning):
            NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.56, alpha: 0.58).setFill()
            path.fill()
        case (.nativeGlass, _):
            color(forScrimTone: glassReadability.scrimTone, alpha: glassReadability.scrimAlpha).setFill()
            path.fill()
        }

        if surface != .nativeGlass {
            let highlightRect = NSRect(x: bounds.minX + 1, y: bounds.minY + 1, width: bounds.width - 2, height: bounds.height * 0.46)
            NSColor.white.withAlphaComponent(statusStyle == .warning ? 0.085 : 0.050).setFill()
            NSBezierPath(roundedRect: highlightRect, xRadius: radius, yRadius: radius).fill()
        }

        let strokeColor: NSColor = switch surface {
        case .darkCapsule:
            NSColor.white.withAlphaComponent(statusStyle == .warning ? 0.22 : 0.15)
        case .lightCapsule:
            NSColor.black.withAlphaComponent(statusStyle == .warning ? 0.17 : 0.11)
        case .fallbackGlass, .nativeGlass:
            surface == .nativeGlass
                ? NSColor.white.withAlphaComponent(statusStyle == .warning ? 0.34 : 0.28)
                : NSColor.black.withAlphaComponent(statusStyle == .warning ? 0.20 : 0.13)
        }
        strokeColor.setStroke()
        path.lineWidth = 0.8
        path.stroke()
    }

    override func layout() {
        super.layout()
        updateNativeGlassCornerRadius()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChanged?()
    }

    private func updateNativeGlassAppearance() {
        guard #available(macOS 26.0, *),
              let glass = nativeGlassView as? NSGlassEffectView else {
            return
        }
        glass.tintColor = statusStyle == .warning
            ? NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.34, alpha: glassReadability.tintAlpha)
            : NSColor(calibratedRed: 0.50, green: 0.66, blue: 0.88, alpha: glassReadability.tintAlpha)
    }

    private func updateNativeGlassCornerRadius() {
        guard #available(macOS 26.0, *),
              let glass = nativeGlassView as? NSGlassEffectView else {
            return
        }
        glass.cornerRadius = currentCornerRadius
    }

    private func configureNativeGlassIfNeeded() {
        nativeGlassView?.removeFromSuperview()
        nativeGlassView = nil
        guard surface == .nativeGlass,
              #available(macOS 26.0, *) else {
            needsDisplay = true
            return
        }
        let glass = NSGlassEffectView(frame: bounds)
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.wantsLayer = true
        glass.cornerRadius = currentCornerRadius
        glass.style = .clear
        glass.tintColor = statusStyle == .warning
            ? NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.34, alpha: glassReadability.tintAlpha)
            : NSColor(calibratedRed: 0.50, green: 0.66, blue: 0.88, alpha: glassReadability.tintAlpha)
        glass.clipsToBounds = true
        addSubview(glass, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        nativeGlassView = glass
        needsDisplay = true
    }
}

private func glassAppearance(for appearance: NSAppearance) -> GlassBackgroundAppearance {
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
}

private func color(forScrimTone tone: HUDTextTone, alpha: CGFloat) -> NSColor {
    switch tone {
    case .light:
        return NSColor.white.withAlphaComponent(alpha)
    case .dark:
        return NSColor.black.withAlphaComponent(alpha)
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

private final class WaveformView: NSView {
    enum Palette {
        case light
        case dark
    }

    var palette: Palette = .light {
        didSet { needsDisplay = true }
    }

    var level: CGFloat = 0 {
        didSet {
            let newValue = min(max(level, 0), 1)
            impulse = min(1, impulse + abs(newValue - targetLevel) * 1.6)
            targetLevel = newValue
        }
    }

    private var animationTimer: Timer?
    private var phase: CGFloat = 0
    private var targetLevel: CGFloat = 0
    private var displayedLevel: CGFloat = 0
    private var impulse: CGFloat = 0
    private var history = Array(repeating: CGFloat(0.08), count: 28)
    private var lastSpeechDate: Date?

    func startAnimating() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.advance()
        }
    }

    func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath()
        path.lineWidth = 1.7
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        let secondsSinceSpeech = lastSpeechDate.map { Date().timeIntervalSince($0) }
        let motion = WaveformMotionResolver.resolve(level: displayedLevel, impulse: impulse, secondsSinceSpeech: secondsSinceSpeech)
        let activeMultiplier: CGFloat = motion.active ? 1.0 : 0.55
        let amplitude = max(
            motion.amplitudeFloor,
            motion.amplitudeFloor + displayedLevel * bounds.height * 0.42 * activeMultiplier + impulse * 1.2
        )
        let midY = bounds.midY
        let samples = 56
        for index in 0...samples {
            let t = CGFloat(index) / CGFloat(samples)
            let x = bounds.minX + t * bounds.width
            let historyIndex = min(history.count - 1, max(0, Int(t * CGFloat(history.count - 1))))
            let localLevel = history[historyIndex]
            let envelope = sin(.pi * t)
            let wave =
                sin(t * .pi * 2.4 + phase) * 0.58 +
                sin(t * .pi * 5.1 + phase * 1.24 + localLevel * 2.6) * 0.28 +
                sin(t * .pi * 9.0 - phase * 0.82) * 0.14
            let y = midY + wave * amplitude * (0.42 + localLevel * 0.95) * max(0.18, envelope)
            if index == 0 {
                path.move(to: NSPoint(x: x, y: y))
            } else {
                path.line(to: NSPoint(x: x, y: y))
            }
        }
        let glowColor: NSColor
        let strokeColor: NSColor
        switch palette {
        case .light:
            glowColor = NSColor.white.withAlphaComponent(0.18)
            strokeColor = NSColor.white.withAlphaComponent(0.91)
        case .dark:
            glowColor = NSColor.black.withAlphaComponent(0.10)
            strokeColor = NSColor(calibratedWhite: 0.08, alpha: 0.82)
        }
        glowColor.setStroke()
        if let glow = path.copy() as? NSBezierPath {
            glow.lineWidth = 3.8
            glow.stroke()
        }

        strokeColor.setStroke()
        path.stroke()
    }

    private func advance() {
        if targetLevel >= WaveformMotionResolver.speechThreshold || impulse > 0.12 {
            lastSpeechDate = Date()
        }
        let smoothing: CGFloat = targetLevel > displayedLevel ? 0.48 : 0.42
        displayedLevel += (targetLevel - displayedLevel) * smoothing
        history.removeFirst()
        let secondsSinceSpeech = lastSpeechDate.map { Date().timeIntervalSince($0) }
        let motion = WaveformMotionResolver.resolve(level: displayedLevel, impulse: impulse, secondsSinceSpeech: secondsSinceSpeech)
        history.append(max(0.025, displayedLevel + impulse * (motion.active ? 0.18 : 0.05)))
        phase += motion.phaseStep
        impulse *= motion.active ? 0.72 : 0.48
        needsDisplay = true
    }
}

private final class ProgressBarView: NSView {
    enum Palette {
        case light(warning: Bool)
        case dark(warning: Bool)
    }

    var palette: Palette = .light(warning: false) {
        didSet { needsDisplay = true }
    }

    var progress: Double = 0 {
        didSet { needsDisplay = true }
    }

    var activityPhase: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let track = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        let colors = colorsForPalette()
        colors.track.setFill()
        track.fill()

        let fillWidth = max(bounds.height, bounds.width * CGFloat(min(max(progress, 0), 1)))
        let fillRect = NSRect(x: bounds.minX, y: bounds.minY, width: fillWidth, height: bounds.height)
        colors.fill.setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: radius, yRadius: radius).fill()

        if progress < 0.90 {
            let shimmerWidth = bounds.width * 0.16
            let x = bounds.minX + (sin(activityPhase * 2.8) * 0.5 + 0.5) * max(1, bounds.width - shimmerWidth)
            let shimmerRect = NSRect(x: x, y: bounds.minY, width: shimmerWidth, height: bounds.height)
            colors.shimmer.setFill()
            NSBezierPath(roundedRect: shimmerRect, xRadius: radius, yRadius: radius).fill()
        }
    }

    private func colorsForPalette() -> (track: NSColor, fill: NSColor, shimmer: NSColor) {
        switch palette {
        case .light(let warning):
            return (
                NSColor.white.withAlphaComponent(warning ? 0.18 : 0.15),
                NSColor.white.withAlphaComponent(warning ? 0.68 : 0.55),
                NSColor.white.withAlphaComponent(0.14)
            )
        case .dark(let warning):
            return (
                NSColor.black.withAlphaComponent(warning ? 0.16 : 0.12),
                NSColor(calibratedWhite: 0.10, alpha: warning ? 0.76 : 0.60),
                NSColor.black.withAlphaComponent(0.10)
            )
        }
    }
}

private extension NSRect {
    var cgRectValue: CGRect {
        CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }

    init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }
}
