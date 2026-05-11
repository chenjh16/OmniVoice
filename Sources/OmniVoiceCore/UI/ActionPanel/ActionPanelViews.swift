import AppKit

final class KeyableActionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ActionPanelKeyView: NSView {
    var onPrimary: (() -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onPrimary?()
        case 53:
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }
}

final class ActionPanelTextView: NSTextView {
    var onPrimary: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onPrimary?()
        case 53:
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }
}

final class ActionPanelBackgroundView: NSView {
    @objc dynamic var cornerRadius: CGFloat = 18 {
        didSet {
            updateNativeGlassCornerRadius()
            needsDisplay = true
        }
    }

    var surface: HUDResolvedSurface = .darkCapsule {
        didSet { configureNativeGlassIfNeeded(); needsDisplay = true }
    }

    var statusTone: HUDStatusTone = .normal {
        didSet {
            updateNativeGlassAppearance()
            needsDisplay = true
        }
    }

    var onEffectiveAppearanceChanged: (() -> Void)?
    var glassReadability = GlassReadabilityResolver.resolve(appearance: .light, status: .normal, role: .actionPanel) {
        didSet {
            updateNativeGlassAppearance()
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    private lazy var nativeGlassBackplate = NativeGlassBackplate(owner: self)
    private var nativeGlassDescriptor: NativeGlassBackplateDescriptor {
        NativeGlassBackplateDescriptor(
            surface: surface,
            role: .actionPanel,
            status: statusTone,
            readability: glassReadability,
            cornerRadius: cornerRadius
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = min(cornerRadius, min(bounds.width, bounds.height) / 2)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        if let fillColors = SurfaceThemeTokens.actionPanelFillColors(surface: surface, status: statusTone) {
            NSGradient(colors: fillColors)?.draw(in: path, angle: -90)
        }

        if surface != .nativeGlass {
            let innerPath = NSBezierPath(
                roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5),
                xRadius: max(0, radius - 1.5),
                yRadius: max(0, radius - 1.5)
            )
            SurfaceThemeTokens.innerStrokeColor(status: statusTone).setStroke()
            innerPath.lineWidth = 0.7
            innerPath.stroke()
        }

        SurfaceThemeTokens.surfaceStrokeColor(role: .actionPanel, surface: surface, status: statusTone).setStroke()
        path.lineWidth = surface == .nativeGlass ? 0.8 : 0.9
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
    }
}

final class ThemedPanelButton: NSButton {
    enum VisualRole {
        case primary
        case secondary
    }

    var visualRole: VisualRole = .secondary {
        didSet { needsDisplay = true }
    }

    var surface: HUDResolvedSurface = .darkCapsule {
        didSet { needsDisplay = true }
    }

    var statusTone: HUDStatusTone = .normal {
        didSet { needsDisplay = true }
    }

    var shortcutLabel: String? {
        didSet { needsDisplay = true }
    }

    var showsMenuIndicator = false {
        didSet { needsDisplay = true }
    }

    var glassTextTone: HUDTextTone = .dark {
        didSet { needsDisplay = true }
    }

    var glassTextHaloColor: NSColor? {
        didSet { needsDisplay = true }
    }

    var glassTextHaloWidth: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    var shortcutFont: NSFont = GlassTypography.actionPanelShortcutFont(for: .darkCapsule) {
        didSet { needsDisplay = true }
    }

    init(role: VisualRole) {
        self.visualRole = role
        super.init(frame: .zero)
        isBordered = false
        focusRingType = .none
        setButtonType(.momentaryChange)
        font = GlassTypography.actionPanelButtonFont(for: .darkCapsule)
        lineBreakMode = .byTruncatingTail
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        let colors = palette()
        colors.fill.setFill()
        path.fill()
        colors.stroke.setStroke()
        path.lineWidth = 0.8
        path.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: colors.text,
            .paragraphStyle: paragraph
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        let shortcut = shortcutLabel?.nilIfBlank
        let shortcutParagraph = NSMutableParagraphStyle()
        shortcutParagraph.alignment = .center
        shortcutParagraph.lineBreakMode = .byClipping
        let shortcutAttributes: [NSAttributedString.Key: Any] = [
            .font: shortcutFont,
            .foregroundColor: colors.text.withAlphaComponent(0.72),
            .paragraphStyle: shortcutParagraph
        ]
        let shortcutSize = shortcut.map { ($0 as NSString).size(withAttributes: shortcutAttributes) } ?? .zero
        let pillPadding: CGFloat = shortcut == nil ? 0 : 10
        let pillWidth = shortcut == nil ? 0 : max(24, shortcutSize.width + pillPadding)
        let gap: CGFloat = shortcut == nil ? 0 : 7
        let indicatorWidth: CGFloat = showsMenuIndicator ? 12 : 0
        let indicatorGap: CGFloat = showsMenuIndicator ? 8 : 0
        let accessoryWidth = gap + pillWidth + indicatorGap + indicatorWidth
        let maxContentWidth = max(24, bounds.width - 24)
        let titleWidth = min(size.width, max(12, maxContentWidth - accessoryWidth))
        let totalWidth = titleWidth + accessoryWidth
        let point = NSPoint(
            x: bounds.midX - totalWidth / 2,
            y: visualTextOriginY(textHeight: size.height)
        )
        let titleRect = NSRect(x: point.x, y: point.y, width: titleWidth, height: size.height + 2)
        GlassTextReadabilityRenderer.draw(
            NSAttributedString(string: title, attributes: attributes),
            in: titleRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            haloColor: glassTextHaloColor,
            haloWidth: glassTextHaloWidth
        )
        var trailingX = titleRect.maxX
        if let shortcut {
            let pillRect = NSRect(
                x: trailingX + gap,
                y: bounds.midY - ActionPanelShortcutMetrics.bubbleHeight / 2 + ActionPanelShortcutMetrics.bubbleCenterYOffset,
                width: pillWidth,
                height: ActionPanelShortcutMetrics.bubbleHeight
            )
            let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 9, yRadius: 9)
            colors.text.withAlphaComponent(surface == .darkCapsule ? 0.12 : 0.10).setFill()
            pillPath.fill()
            let shortcutRect = NSRect(
                x: pillRect.minX + 2,
                y: ShortcutGlyphLayoutResolver.glyphDrawOriginY(
                    bubbleMidY: pillRect.midY,
                    glyphHeight: shortcutSize.height,
                    shortcut: shortcut
                ),
                width: max(1, pillRect.width - 4),
                height: shortcutSize.height + 2
            )
            GlassTextReadabilityRenderer.draw(
                NSAttributedString(string: shortcut, attributes: shortcutAttributes),
                in: shortcutRect,
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                haloColor: glassTextHaloColor?.withAlphaComponent(0.78),
                haloWidth: glassTextHaloWidth * 0.78
            )
            trailingX = pillRect.maxX
        }
        if showsMenuIndicator {
            let chevronX = trailingX + indicatorGap
            let chevronCenterY = bounds.midY + 0.5
            let path = NSBezierPath()
            path.move(to: NSPoint(x: chevronX, y: chevronCenterY + 2))
            path.line(to: NSPoint(x: chevronX + 4, y: chevronCenterY - 2))
            path.line(to: NSPoint(x: chevronX + 8, y: chevronCenterY + 2))
            colors.text.withAlphaComponent(0.72).setStroke()
            path.lineWidth = 1.35
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }

    private func visualTextOriginY(textHeight: CGFloat, centerY: CGFloat? = nil) -> CGFloat {
        (centerY ?? bounds.midY) - textHeight / 2 - 0.5
    }

    private func palette() -> (fill: NSColor, stroke: NSColor, text: NSColor) {
        SurfaceThemeTokens.actionPanelButtonPalette(
            visualRole: visualRole,
            surface: surface,
            status: statusTone,
            highlighted: isHighlighted,
            glassTextTone: glassTextTone
        )
    }
}
