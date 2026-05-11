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

    private lazy var nativeGlassBackplate = NativeGlassBackplate(owner: self)
    private var nativeGlassDescriptor: NativeGlassBackplateDescriptor {
        NativeGlassBackplateDescriptor(
            surface: surface,
            role: .hud,
            status: nativeGlassStatusTone,
            readability: glassReadability,
            cornerRadius: currentCornerRadius
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = currentCornerRadius
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        let statusTone = nativeGlassStatusTone
        if let fillColor = SurfaceThemeTokens.capsuleFillColor(surface: surface, status: statusTone) {
            fillColor.setFill()
            path.fill()
        }

        if surface != .nativeGlass {
            let highlightRect = NSRect(x: bounds.minX + 1, y: bounds.minY + 1, width: bounds.width - 2, height: bounds.height * 0.46)
            SurfaceThemeTokens.capsuleHighlightColor(status: statusTone).setFill()
            NSBezierPath(roundedRect: highlightRect, xRadius: radius, yRadius: radius).fill()
        }

        let strokeColor = SurfaceThemeTokens.surfaceStrokeColor(role: .hud, surface: surface, status: statusTone)
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
        nativeGlassBackplate.updateAppearance(nativeGlassDescriptor)
    }

    private func updateNativeGlassCornerRadius() {
        nativeGlassBackplate.updateCornerRadius(nativeGlassDescriptor)
    }

    private func configureNativeGlassIfNeeded() {
        nativeGlassBackplate.configureIfNeeded(nativeGlassDescriptor)
        needsDisplay = true
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
