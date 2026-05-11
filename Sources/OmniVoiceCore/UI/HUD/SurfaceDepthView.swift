import AppKit

public enum SurfaceDepthRole: Equatable, Sendable {
    case hud
    case actionPanel
}

public struct SurfaceDepthInsets: Equatable, Sendable {
    public let left: CGFloat
    public let right: CGFloat
    public let top: CGFloat
    public let bottom: CGFloat

    public init(left: CGFloat, right: CGFloat, top: CGFloat, bottom: CGFloat) {
        self.left = left
        self.right = right
        self.top = top
        self.bottom = bottom
    }

    public init(horizontal: CGFloat, vertical: CGFloat) {
        self.init(left: horizontal, right: horizontal, top: vertical, bottom: vertical)
    }

    public var horizontal: CGFloat { left + right }
    public var vertical: CGFloat { top + bottom }
}

public struct SurfaceDepthParameters: Equatable, Sendable {
    public let ambientAlpha: CGFloat
    public let ambientBlur: CGFloat
    public let dropAlpha: CGFloat
    public let dropBlur: CGFloat
    public let dropOffsetY: CGFloat
    public let contactAlpha: CGFloat
    public let contactBlur: CGFloat
    public let contactOffsetY: CGFloat
    public let rimAlpha: CGFloat
    public let shadowSourceAlpha: CGFloat

    public var hasVisibleDepth: Bool {
        ambientAlpha > 0 || dropAlpha > 0 || contactAlpha > 0 || rimAlpha > 0
    }
}

enum NativeGlassSurfaceStyle {
    static let topSheenAlpha: CGFloat = 0
    static let bottomShadeAlpha: CGFloat = 0

    static func tintColor(status: HUDStatusTone, readability: GlassReadabilityStyle) -> NSColor? {
        switch status {
        case .normal:
            guard readability.tintAlpha > 0 else { return nil }
            return NSColor(calibratedWhite: 0.0, alpha: readability.tintAlpha)
        case .warning:
            return NSColor(calibratedRed: 1.0, green: 0.56, blue: 0.20, alpha: readability.tintAlpha)
        }
    }

    static func overlayColor(status: HUDStatusTone, readability: GlassReadabilityStyle) -> NSColor {
        switch status {
        case .normal:
            return NSColor(calibratedWhite: 0.0, alpha: readability.scrimAlpha)
        case .warning:
            return NSColor(calibratedRed: 0.95, green: 0.46, blue: 0.16, alpha: readability.scrimAlpha)
        }
    }

    static func innerRimAlpha(status: HUDStatusTone) -> CGFloat {
        status == .warning ? 0.24 : 0.18
    }

    static func topSheenAlpha(role: GlassSurfaceRole, status: HUDStatusTone) -> CGFloat {
        switch role {
        case .hud:
            return topSheenAlpha
        case .actionPanel:
            return topSheenAlpha
        }
    }

    static func bottomShadeAlpha(role: GlassSurfaceRole, status: HUDStatusTone) -> CGFloat {
        switch role {
        case .hud:
            return bottomShadeAlpha
        case .actionPanel:
            return bottomShadeAlpha
        }
    }

    static func innerRimAlpha(status: HUDStatusTone, role: GlassSurfaceRole) -> CGFloat {
        switch role {
        case .hud:
            return innerRimAlpha(status: status)
        case .actionPanel:
            return status == .warning ? 0.32 : 0.28
        }
    }

    @available(macOS 26.0, *)
    static func glassStyle(role: GlassSurfaceRole, status: HUDStatusTone) -> NSGlassEffectView.Style {
        .regular
    }
}

public enum SurfaceDepthMetrics {
    public static let hudInsets = SurfaceDepthInsets(left: 22, right: 22, top: 18, bottom: 28)
    public static let actionPanelInsets = SurfaceDepthInsets(left: 48, right: 48, top: 40, bottom: 68)

    public static func insets(for role: SurfaceDepthRole) -> SurfaceDepthInsets {
        switch role {
        case .hud:
            hudInsets
        case .actionPanel:
            actionPanelInsets
        }
    }

    public static func windowSize(forVisualSize size: CGSize, role: SurfaceDepthRole) -> CGSize {
        let insets = insets(for: role)
        return CGSize(width: size.width + insets.horizontal, height: size.height + insets.vertical)
    }

    public static func windowFrame(forVisualFrame frame: CGRect, role: SurfaceDepthRole) -> CGRect {
        let insets = insets(for: role)
        return CGRect(
            x: frame.minX - insets.left,
            y: frame.minY - insets.bottom,
            width: frame.width + insets.horizontal,
            height: frame.height + insets.vertical
        )
    }

    public static func visualFrame(forWindowFrame frame: CGRect, role: SurfaceDepthRole) -> CGRect {
        let insets = insets(for: role)
        return CGRect(
            x: frame.minX + insets.left,
            y: frame.minY + insets.bottom,
            width: max(1, frame.width - insets.horizontal),
            height: max(1, frame.height - insets.vertical)
        )
    }

    public static func surfaceRect(in bounds: CGRect, role: SurfaceDepthRole) -> CGRect {
        let insets = insets(for: role)
        return CGRect(
            x: bounds.minX + insets.left,
            y: bounds.minY + insets.top,
            width: max(1, bounds.width - insets.horizontal),
            height: max(1, bounds.height - insets.vertical)
        )
    }

    public static func parameters(
        role: SurfaceDepthRole,
        surface: HUDResolvedSurface,
        status: HUDStatusTone
    ) -> SurfaceDepthParameters {
        let warningScale: CGFloat = status == .warning ? 1.18 : 1.0
        switch (role, surface) {
        case (.hud, .darkCapsule):
            return SurfaceDepthParameters(
                ambientAlpha: 0.26 * warningScale,
                ambientBlur: 28,
                dropAlpha: 0.42 * warningScale,
                dropBlur: 27,
                dropOffsetY: -8,
                contactAlpha: 0.38 * warningScale,
                contactBlur: 13,
                contactOffsetY: -6,
                rimAlpha: 0.14,
                shadowSourceAlpha: 0.32
            )
        case (.hud, .lightCapsule):
            return SurfaceDepthParameters(
                ambientAlpha: 0.23 * warningScale,
                ambientBlur: 28,
                dropAlpha: 0.36 * warningScale,
                dropBlur: 27,
                dropOffsetY: -8,
                contactAlpha: 0.30 * warningScale,
                contactBlur: 13,
                contactOffsetY: -6,
                rimAlpha: 0.11,
                shadowSourceAlpha: 0.30
            )
        case (.hud, .fallbackGlass), (.hud, .nativeGlass):
            return SurfaceDepthParameters(
                ambientAlpha: 0.28 * warningScale,
                ambientBlur: 30,
                dropAlpha: 0.40 * warningScale,
                dropBlur: 28,
                dropOffsetY: -8,
                contactAlpha: 0.34 * warningScale,
                contactBlur: 14,
                contactOffsetY: -6,
                rimAlpha: 0.19,
                shadowSourceAlpha: 0.32
            )
        case (.actionPanel, .darkCapsule):
            return SurfaceDepthParameters(
                ambientAlpha: 0.42 * warningScale,
                ambientBlur: 48,
                dropAlpha: 0.58 * warningScale,
                dropBlur: 44,
                dropOffsetY: -20,
                contactAlpha: 0.48 * warningScale,
                contactBlur: 22,
                contactOffsetY: -16,
                rimAlpha: 0.16,
                shadowSourceAlpha: 0.36
            )
        case (.actionPanel, .lightCapsule):
            return SurfaceDepthParameters(
                ambientAlpha: 0.31 * warningScale,
                ambientBlur: 48,
                dropAlpha: 0.44 * warningScale,
                dropBlur: 44,
                dropOffsetY: -20,
                contactAlpha: 0.36 * warningScale,
                contactBlur: 22,
                contactOffsetY: -16,
                rimAlpha: 0.12,
                shadowSourceAlpha: 0.34
            )
        case (.actionPanel, .fallbackGlass), (.actionPanel, .nativeGlass):
            return SurfaceDepthParameters(
                ambientAlpha: 0.38 * warningScale,
                ambientBlur: 50,
                dropAlpha: 0.52 * warningScale,
                dropBlur: 46,
                dropOffsetY: -20,
                contactAlpha: 0.42 * warningScale,
                contactBlur: 23,
                contactOffsetY: -16,
                rimAlpha: 0.19,
                shadowSourceAlpha: 0.36
            )
        }
    }
}

final class SurfaceShadowView: NSView {
    let role: SurfaceDepthRole

    var surface: HUDResolvedSurface = .darkCapsule {
        didSet { needsDisplay = true }
    }

    var status: HUDStatusTone = .normal {
        didSet { needsDisplay = true }
    }

    @objc dynamic var cornerRadius: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    init(role: SurfaceDepthRole) {
        self.role = role
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let rect = SurfaceDepthMetrics.surfaceRect(in: bounds, role: role).insetBy(dx: 0.5, dy: 0.5)
        let radius = resolvedCornerRadius(for: rect)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        let parameters = SurfaceDepthMetrics.parameters(role: role, surface: surface, status: status)
        drawShadow(
            path: path,
            alpha: parameters.ambientAlpha,
            blur: parameters.ambientBlur,
            offsetY: 0,
            sourceAlpha: parameters.shadowSourceAlpha
        )
        drawShadow(
            path: path,
            alpha: parameters.dropAlpha,
            blur: parameters.dropBlur,
            offsetY: parameters.dropOffsetY,
            sourceAlpha: parameters.shadowSourceAlpha
        )
        drawShadow(
            path: path,
            alpha: parameters.contactAlpha,
            blur: parameters.contactBlur,
            offsetY: parameters.contactOffsetY,
            sourceAlpha: min(0.44, parameters.shadowSourceAlpha + 0.10)
        )
        clearShadowSourceInterior(path: path)
        drawOuterRim(path: path, alpha: parameters.rimAlpha)
    }

    private func resolvedCornerRadius(for rect: NSRect) -> CGFloat {
        let fallback = rect.height / 2
        return min(cornerRadius > 0 ? cornerRadius : fallback, min(rect.width, rect.height) / 2)
    }

    private func drawShadow(
        path: NSBezierPath,
        alpha: CGFloat,
        blur: CGFloat,
        offsetY: CGFloat,
        sourceAlpha: CGFloat
    ) {
        guard alpha > 0, blur > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(alpha)
        shadow.shadowBlurRadius = blur
        shadow.shadowOffset = NSSize(width: 0, height: offsetY)
        shadow.set()
        NSColor.black.withAlphaComponent(sourceAlpha).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func clearShadowSourceInterior(path: NSBezierPath) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawOuterRim(path: NSBezierPath, alpha: CGFloat) {
        guard alpha > 0 else { return }
        let color: NSColor = switch surface {
        case .darkCapsule:
            NSColor.white.withAlphaComponent(alpha)
        case .lightCapsule:
            NSColor.black.withAlphaComponent(alpha)
        case .fallbackGlass, .nativeGlass:
            NSColor.white.withAlphaComponent(alpha)
        }
        color.setStroke()
        path.lineWidth = role == .hud ? 0.8 : 0.9
        path.stroke()
    }
}
