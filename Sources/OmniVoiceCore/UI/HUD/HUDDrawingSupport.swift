import AppKit

func glassAppearance(for appearance: NSAppearance) -> GlassBackgroundAppearance {
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
}

func textColor(for tone: HUDTextTone) -> NSColor {
    switch tone {
    case .light:
        return NSColor.white.withAlphaComponent(0.96)
    case .dark:
        return NSColor(calibratedWhite: 0.08, alpha: 0.96)
    }
}

func textHaloColor(for tone: HUDTextTone, alpha: CGFloat) -> NSColor? {
    guard alpha > 0 else { return nil }
    switch tone {
    case .light:
        return NSColor.black.withAlphaComponent(alpha)
    case .dark:
        return NSColor.white.withAlphaComponent(alpha)
    }
}

enum GlassTextReadabilityRenderer {
    static func haloAttributedString(
        from attributedString: NSAttributedString,
        haloColor: NSColor?,
        haloWidth: CGFloat
    ) -> NSAttributedString? {
        guard let haloColor, haloWidth > 0, attributedString.length > 0 else {
            return nil
        }
        let halo = NSMutableAttributedString(attributedString: attributedString)
        halo.addAttributes(
            [
                .strokeColor: haloColor,
                .strokeWidth: haloWidth
            ],
            range: NSRange(location: 0, length: halo.length)
        )
        return halo
    }

    static func draw(
        _ attributedString: NSAttributedString,
        in rect: NSRect,
        options: NSString.DrawingOptions = [],
        haloColor: NSColor?,
        haloWidth: CGFloat
    ) {
        if let halo = haloAttributedString(
            from: attributedString,
            haloColor: haloColor,
            haloWidth: haloWidth
        ) {
            halo.draw(with: rect, options: options)
        }
        attributedString.draw(with: rect, options: options)
    }
}

enum GlassTypography {
    static func hudTextFont(for surface: HUDResolvedSurface) -> NSFont {
        .systemFont(ofSize: 12.5, weight: compactWeight(for: surface))
    }

    static func hudBadgeFont(for surface: HUDResolvedSurface) -> NSFont {
        .systemFont(ofSize: HUDDraftBadgeMetrics.fontSize, weight: compactWeight(for: surface))
    }

    static func actionPanelTitleFont(for surface: HUDResolvedSurface) -> NSFont {
        .systemFont(ofSize: 14.5, weight: panelWeight(for: surface))
    }

    static func actionPanelBodyFont(for surface: HUDResolvedSurface) -> NSFont {
        .systemFont(ofSize: 14, weight: panelWeight(for: surface))
    }

    static func actionPanelButtonFont(for surface: HUDResolvedSurface) -> NSFont {
        .systemFont(ofSize: 13, weight: panelWeight(for: surface))
    }

    static func actionPanelShortcutFont(for surface: HUDResolvedSurface) -> NSFont {
        .systemFont(ofSize: 9.5, weight: compactWeight(for: surface))
    }

    static func compactWeight(for surface: HUDResolvedSurface) -> NSFont.Weight {
        surface == .nativeGlass ? .bold : .semibold
    }

    static func panelWeight(for surface: HUDResolvedSurface) -> NSFont.Weight {
        surface == .nativeGlass ? .bold : .semibold
    }

    static let panelButtonHaloAlphaScale: CGFloat = 0.90
    static let panelButtonHaloWidthScale: CGFloat = 1.0
}

final class HaloTextField: NSTextField {
    var textHaloColor: NSColor? {
        didSet { needsDisplay = true }
    }

    var textHaloWidth: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    convenience init(labelWithString string: String) {
        self.init(frame: .zero)
        stringValue = string
        isEditable = false
        isSelectable = false
        isBordered = false
        drawsBackground = false
        backgroundColor = .clear
        focusRingType = .none
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !stringValue.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = lineBreakMode
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: NSFont.systemFontSize, weight: .regular),
            .foregroundColor: textColor ?? .labelColor,
            .paragraphStyle: paragraph
        ]
        if let shadow {
            attributes[.shadow] = shadow
        }
        let attributed = NSAttributedString(string: stringValue, attributes: attributes)
        let textBounds = attributed.boundingRect(
            with: NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let drawRect = NSRect(
            x: bounds.minX,
            y: bounds.midY - textBounds.height / 2 - textBounds.origin.y,
            width: bounds.width,
            height: max(bounds.height, textBounds.height)
        )
        GlassTextReadabilityRenderer.draw(
            attributed,
            in: drawRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            haloColor: textHaloColor,
            haloWidth: textHaloWidth
        )
    }
}

func color(forScrimTone tone: HUDTextTone, alpha: CGFloat) -> NSColor {
    switch tone {
    case .light:
        return NSColor.white.withAlphaComponent(alpha)
    case .dark:
        return NSColor.black.withAlphaComponent(alpha)
    }
}

extension NSRect {
    var cgRectValue: CGRect {
        CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }

    init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }
}
