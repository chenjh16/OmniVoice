import AppKit

final class DraftBadgeView: NSView {
    var text: String = "" {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    var textColor: NSColor = .white {
        didSet { needsDisplay = true }
    }

    var fillColor: NSColor = NSColor.white.withAlphaComponent(0.16) {
        didSet { needsDisplay = true }
    }

    var borderColor: NSColor = NSColor.white.withAlphaComponent(0.20) {
        didSet { needsDisplay = true }
    }

    var borderWidth: CGFloat = 0.6 {
        didSet { needsDisplay = true }
    }

    private let badgeFont = NSFont.systemFont(ofSize: HUDDraftBadgeMetrics.fontSize, weight: .semibold)

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: HUDDraftBadgeMetrics.width(for: text, font: badgeFont),
            height: HUDDraftBadgeMetrics.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        fillColor.setFill()
        path.fill()
        if borderWidth > 0 {
            borderColor.setStroke()
            path.lineWidth = borderWidth
            path.stroke()
        }

        guard !text.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: badgeFont,
                .foregroundColor: textColor,
                .paragraphStyle: paragraph
            ]
        )
        let textBounds = attributed.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let drawRect = NSRect(
            x: bounds.midX - textBounds.width / 2 - textBounds.origin.x,
            y: bounds.midY - textBounds.height / 2 - textBounds.origin.y,
            width: textBounds.width,
            height: textBounds.height
        )
        attributed.draw(with: drawRect, options: [.usesLineFragmentOrigin])
    }
}

final class CapsuleBackgroundView: NSView {
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

final class WaveformView: NSView {
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

final class ProgressBarView: NSView {
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
