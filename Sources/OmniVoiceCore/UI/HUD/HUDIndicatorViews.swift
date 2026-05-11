import AppKit

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

    var requestPhase: TranscriptionRequestPhase = .preparingRequest {
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
            let accent = accentColor(lightText: true, warning: warning)
            return (
                NSColor.white.withAlphaComponent(warning ? 0.18 : 0.15),
                accent.fill,
                accent.shimmer
            )
        case .dark(let warning):
            let accent = accentColor(lightText: false, warning: warning)
            return (
                NSColor.black.withAlphaComponent(warning ? 0.16 : 0.12),
                accent.fill,
                accent.shimmer
            )
        }
    }

    private func accentColor(lightText: Bool, warning: Bool) -> (fill: NSColor, shimmer: NSColor) {
        if warning {
            return lightText
                ? (NSColor.white.withAlphaComponent(0.68), NSColor.white.withAlphaComponent(0.14))
                : (NSColor(calibratedWhite: 0.10, alpha: 0.76), NSColor.black.withAlphaComponent(0.10))
        }
        let alpha: CGFloat = switch requestPhase {
        case .preparingRequest: 0.48
        case .connecting: 0.58
        case .responseReceived: 0.66
        case .waitingForFirstDelta: 0.72
        case .streaming: 0.82
        case .completed: 0.90
        }
        let shimmerAlpha: CGFloat = switch requestPhase {
        case .preparingRequest: 0.10
        case .connecting: 0.16
        case .responseReceived: 0.18
        case .waitingForFirstDelta: 0.20
        case .streaming: 0.24
        case .completed: 0.18
        }
        switch (lightText, requestPhase) {
        case (true, .preparingRequest):
            return (NSColor.white.withAlphaComponent(alpha), NSColor.white.withAlphaComponent(shimmerAlpha))
        case (true, .connecting), (true, .responseReceived), (true, .waitingForFirstDelta):
            return (NSColor.systemBlue.withAlphaComponent(alpha), NSColor.systemCyan.withAlphaComponent(shimmerAlpha))
        case (true, .streaming), (true, .completed):
            return (NSColor.systemTeal.withAlphaComponent(alpha), NSColor.systemCyan.withAlphaComponent(shimmerAlpha))
        case (false, .preparingRequest):
            return (NSColor(calibratedWhite: 0.10, alpha: 0.60), NSColor.black.withAlphaComponent(0.10))
        case (false, .connecting), (false, .responseReceived), (false, .waitingForFirstDelta):
            return (NSColor.systemBlue.withAlphaComponent(alpha), NSColor.systemBlue.withAlphaComponent(shimmerAlpha))
        case (false, .streaming), (false, .completed):
            return (NSColor.systemTeal.withAlphaComponent(alpha), NSColor.systemTeal.withAlphaComponent(shimmerAlpha))
        }
    }
}
