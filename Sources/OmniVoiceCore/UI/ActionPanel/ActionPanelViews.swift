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

    private var nativeGlassView: NSView?
    var onEffectiveAppearanceChanged: (() -> Void)?
    var glassReadability = GlassReadabilityResolver.resolve(appearance: .light, status: .normal) {
        didSet {
            updateNativeGlassAppearance()
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let radius = min(cornerRadius, min(bounds.width, bounds.height) / 2)
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        let fillColors: [NSColor]? = switch (surface, statusTone) {
        case (.darkCapsule, .normal):
            [
                NSColor(calibratedRed: 0.050, green: 0.056, blue: 0.068, alpha: 0.99),
                NSColor(calibratedRed: 0.020, green: 0.023, blue: 0.030, alpha: 0.99)
            ]
        case (.darkCapsule, .warning):
            [
                NSColor(calibratedRed: 0.270, green: 0.135, blue: 0.072, alpha: 0.99),
                NSColor(calibratedRed: 0.135, green: 0.060, blue: 0.032, alpha: 0.99)
            ]
        case (.lightCapsule, .normal):
            [
                NSColor(calibratedRed: 0.988, green: 0.978, blue: 0.952, alpha: 0.985),
                NSColor(calibratedRed: 0.950, green: 0.940, blue: 0.915, alpha: 0.970)
            ]
        case (.lightCapsule, .warning):
            [
                NSColor(calibratedRed: 1.0, green: 0.895, blue: 0.765, alpha: 0.985),
                NSColor(calibratedRed: 0.970, green: 0.790, blue: 0.585, alpha: 0.965)
            ]
        case (.fallbackGlass, .normal):
            [
                NSColor(calibratedWhite: 1.0, alpha: 0.50),
                NSColor(calibratedWhite: 0.92, alpha: 0.36)
            ]
        case (.fallbackGlass, .warning):
            [
                NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.68, alpha: 0.58),
                NSColor(calibratedRed: 0.95, green: 0.66, blue: 0.44, alpha: 0.42)
            ]
        case (.nativeGlass, _):
            nil
        }
        if let fillColors {
            NSGradient(colors: fillColors)?.draw(in: path, angle: -90)
        } else if surface == .nativeGlass {
            color(forScrimTone: glassReadability.scrimTone, alpha: glassReadability.scrimAlpha).setFill()
            path.fill()
        }

        let innerPath = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5),
            xRadius: max(0, radius - 1.5),
            yRadius: max(0, radius - 1.5)
        )
        NSColor.white.withAlphaComponent(statusTone == .warning ? 0.055 : 0.045).setStroke()
        innerPath.lineWidth = 0.7
        innerPath.stroke()

        let strokeColor: NSColor = switch surface {
        case .darkCapsule:
            NSColor.white.withAlphaComponent(statusTone == .warning ? 0.23 : 0.16)
        case .lightCapsule:
            NSColor.black.withAlphaComponent(statusTone == .warning ? 0.18 : 0.12)
        case .fallbackGlass, .nativeGlass:
            surface == .nativeGlass
                ? NSColor.white.withAlphaComponent(statusTone == .warning ? 0.34 : 0.28)
                : NSColor.black.withAlphaComponent(statusTone == .warning ? 0.24 : 0.14)
        }
        strokeColor.setStroke()
        path.lineWidth = 0.9
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
        glass.tintColor = statusTone == .warning
            ? NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.34, alpha: glassReadability.tintAlpha)
            : NSColor(calibratedRed: 0.50, green: 0.66, blue: 0.88, alpha: glassReadability.tintAlpha)
    }

    private func updateNativeGlassCornerRadius() {
        guard #available(macOS 26.0, *),
              let glass = nativeGlassView as? NSGlassEffectView else {
            return
        }
        glass.cornerRadius = cornerRadius
    }

    private func configureNativeGlassIfNeeded() {
        nativeGlassView?.removeFromSuperview()
        nativeGlassView = nil
        guard surface == .nativeGlass,
              #available(macOS 26.0, *) else {
            return
        }
        let glass = NSGlassEffectView(frame: bounds)
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.wantsLayer = true
        glass.cornerRadius = cornerRadius
        glass.style = .clear
        glass.tintColor = statusTone == .warning
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

    init(role: VisualRole) {
        self.visualRole = role
        super.init(frame: .zero)
        isBordered = false
        focusRingType = .none
        setButtonType(.momentaryChange)
        font = .systemFont(ofSize: 13, weight: .semibold)
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
            .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold),
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
        (title as NSString).draw(
            with: titleRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attributes
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
            (shortcut as NSString).draw(
                with: shortcutRect,
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: shortcutAttributes
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
        let pressed = isHighlighted ? 0.12 : 0
        if surface == .nativeGlass {
            let text = textColor(for: glassTextTone)
            switch visualRole {
            case .primary:
                return (
                    statusTone == .warning
                        ? NSColor(calibratedRed: 0.90 - pressed, green: 0.40, blue: 0.14, alpha: 0.88)
                        : NSColor(calibratedRed: 0.12, green: 0.43 - pressed, blue: 0.90 - pressed, alpha: 0.82),
                    text.withAlphaComponent(0.14),
                    .white
                )
            case .secondary:
                return (
                    text.withAlphaComponent(isHighlighted ? 0.16 : 0.09),
                    text.withAlphaComponent(0.14),
                    text.withAlphaComponent(0.94)
                )
            }
        }
        let lightSurface = surface == .lightCapsule || surface == .fallbackGlass || surface == .nativeGlass
        switch (visualRole, lightSurface, statusTone) {
        case (.primary, false, .normal):
            return (
                NSColor(calibratedRed: 0.15, green: 0.47 - pressed, blue: 0.92 - pressed, alpha: 0.96),
                NSColor.white.withAlphaComponent(0.22),
                .white
            )
        case (.primary, false, .warning):
            return (
                NSColor(calibratedRed: 0.94 - pressed, green: 0.46 - pressed, blue: 0.20, alpha: 0.96),
                NSColor.white.withAlphaComponent(0.22),
                .white
            )
        case (.secondary, false, _):
            return (
                NSColor.white.withAlphaComponent(isHighlighted ? 0.18 : 0.11),
                NSColor.white.withAlphaComponent(0.14),
                NSColor.white.withAlphaComponent(0.92)
            )
        case (.primary, true, .normal):
            return (
                NSColor(calibratedRed: 0.12, green: 0.43 - pressed, blue: 0.90 - pressed, alpha: 0.88),
                NSColor.black.withAlphaComponent(0.12),
                .white
            )
        case (.primary, true, .warning):
            return (
                NSColor(calibratedRed: 0.86 - pressed, green: 0.36, blue: 0.10, alpha: 0.84),
                NSColor.black.withAlphaComponent(0.14),
                .white
            )
        case (.secondary, true, _):
            return (
                NSColor.black.withAlphaComponent(isHighlighted ? 0.12 : 0.07),
                NSColor.black.withAlphaComponent(0.12),
                NSColor(calibratedWhite: 0.10, alpha: 0.92)
            )
        }
    }
}
