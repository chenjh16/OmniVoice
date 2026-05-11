import AppKit

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
    private var nativeGlassScrimView: GlassScrimView?
    var onEffectiveAppearanceChanged: (() -> Void)?
    var glassReadability = GlassReadabilityResolver.resolve(appearance: .light, status: .normal, role: .hud) {
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
            break
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
        guard #available(macOS 26.0, *) else {
            return
        }
        if let glass = nativeGlassView as? NSGlassEffectView {
            glass.style = NativeGlassSurfaceStyle.glassStyle(role: .hud, status: nativeGlassStatusTone)
            glass.tintColor = NativeGlassSurfaceStyle.tintColor(status: nativeGlassStatusTone, readability: glassReadability)
            glass.alphaValue = 1
        } else if let effect = nativeGlassView as? NSVisualEffectView {
            effect.alphaValue = glassReadability.materialAlpha
            effect.appearance = NSAppearance(named: .darkAqua)
        }
        applyLiquidGlassOverlay(to: nativeGlassScrimView)
    }

    private func updateNativeGlassCornerRadius() {
        if #available(macOS 26.0, *),
           let glass = nativeGlassView as? NSGlassEffectView {
            glass.cornerRadius = currentCornerRadius
        } else if let effect = nativeGlassView as? NSVisualEffectView {
            effect.layer?.cornerRadius = currentCornerRadius
        }
        nativeGlassScrimView?.cornerRadius = currentCornerRadius
    }

    private func configureNativeGlassIfNeeded() {
        nativeGlassView?.removeFromSuperview()
        nativeGlassView = nil
        nativeGlassScrimView?.removeFromSuperview()
        nativeGlassScrimView = nil
        guard surface == .nativeGlass,
              #available(macOS 26.0, *) else {
            needsDisplay = true
            return
        }
        let glass = NSGlassEffectView(frame: bounds)
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.cornerRadius = currentCornerRadius
        glass.style = NativeGlassSurfaceStyle.glassStyle(role: .hud, status: nativeGlassStatusTone)
        glass.tintColor = NativeGlassSurfaceStyle.tintColor(status: nativeGlassStatusTone, readability: glassReadability)
        glass.alphaValue = 1
        addSubview(glass, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        let scrim = GlassScrimView()
        scrim.translatesAutoresizingMaskIntoConstraints = false
        scrim.cornerRadius = currentCornerRadius
        applyLiquidGlassOverlay(to: scrim)
        addSubview(scrim, positioned: .above, relativeTo: glass)
        NSLayoutConstraint.activate([
            scrim.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrim.topAnchor.constraint(equalTo: topAnchor),
            scrim.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        nativeGlassView = glass
        nativeGlassScrimView = scrim
        needsDisplay = true
    }

    private func applyLiquidGlassOverlay(to scrim: GlassScrimView?) {
        guard let scrim else { return }
        let status = nativeGlassStatusTone
        scrim.color = NativeGlassSurfaceStyle.overlayColor(status: status, readability: glassReadability)
        scrim.topSheenAlpha = NativeGlassSurfaceStyle.topSheenAlpha(role: .hud, status: status)
        scrim.bottomShadeAlpha = NativeGlassSurfaceStyle.bottomShadeAlpha(role: .hud, status: status)
        scrim.innerRimAlpha = NativeGlassSurfaceStyle.innerRimAlpha(status: status, role: .hud)
    }

    private var nativeGlassStatusTone: HUDStatusTone {
        statusStyle == .warning ? .warning : .normal
    }
}

final class GlassScrimView: NSView {
    var color: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    var cornerRadius: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    var topSheenAlpha: CGFloat = 0.16 {
        didSet { needsDisplay = true }
    }

    var bottomShadeAlpha: CGFloat = 0.16 {
        didSet { needsDisplay = true }
    }

    var innerRimAlpha: CGFloat = 0.30 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        color.setFill()
        path.fill()

        if let sheen = NSGradient(colors: [
            NSColor.white.withAlphaComponent(topSheenAlpha),
            NSColor.white.withAlphaComponent(0)
        ]) {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let sheenRect = NSRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: rect.height * 0.55
            )
            sheen.draw(in: sheenRect, angle: -90)
            NSGraphicsContext.restoreGraphicsState()
        }

        if let shade = NSGradient(colors: [
            NSColor.black.withAlphaComponent(0),
            NSColor.black.withAlphaComponent(bottomShadeAlpha)
        ]) {
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let shadeRect = NSRect(
                x: rect.minX,
                y: rect.minY + rect.height * 0.36,
                width: rect.width,
                height: rect.height * 0.64
            )
            shade.draw(in: shadeRect, angle: -90)
            NSGraphicsContext.restoreGraphicsState()
        }

        NSColor.white.withAlphaComponent(innerRimAlpha).setStroke()
        path.lineWidth = 0.9
        path.stroke()
    }
}
