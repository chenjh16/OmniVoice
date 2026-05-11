import AppKit

enum HUDLivePreviewTailFitter {
    static func visibleTail(text: String, availableWidth: CGFloat, font: NSFont) -> String {
        guard availableWidth > 1, !text.isEmpty else { return "" }
        if measuredWidth(text, font: font) <= availableWidth {
            return text
        }
        let characters = Array(text)
        var lower = 0
        var upper = characters.count
        var best = ""
        while lower <= upper {
            let middle = (lower + upper) / 2
            let candidate = String(characters.suffix(middle))
            if measuredWidth(candidate, font: font) <= availableWidth {
                best = candidate
                lower = middle + 1
            } else {
                upper = middle - 1
            }
        }
        return best.isEmpty ? String(characters.suffix(1)) : best
    }

    static func measuredWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

final class LivePreviewTextView: NSView {
    var text: String = "" {
        didSet { needsDisplay = true }
    }

    var font: NSFont = .systemFont(ofSize: 12.5, weight: .semibold) {
        didSet { needsDisplay = true }
    }

    var textColor: NSColor = .white {
        didSet { needsDisplay = true }
    }

    var textHaloColor: NSColor? {
        didSet { needsDisplay = true }
    }

    var textHaloWidth: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    var fadeTailEnabled: Bool = false {
        didSet { needsDisplay = true }
    }

    var fadeWidth: CGFloat = HUDLivePreviewLayoutMetrics.fadeWidth {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: HUDLivePreviewLayoutMetrics.textHeight)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = frame.size
        super.setFrameSize(newSize)
        if oldSize != newSize {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 1, bounds.height > 1, !text.isEmpty else { return }
        let visibleText = HUDLivePreviewTailFitter.visibleTail(
            text: text,
            availableWidth: bounds.width,
            font: font
        )
        guard !visibleText.isEmpty else { return }
        guard let context = NSGraphicsContext.current?.cgContext else {
            drawVisibleText(visibleText)
            return
        }

        context.saveGState()
        NSBezierPath(rect: bounds).addClip()
        if fadeTailEnabled {
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            drawVisibleText(visibleText)
            applyLeftFadeMask(in: context)
            context.endTransparencyLayer()
        } else {
            drawVisibleText(visibleText)
        }
        context.restoreGState()
    }

    private func drawVisibleText(_ visibleText: String) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineBreakMode = .byClipping
        let attributed = attributedText(visibleText, paragraph: paragraph)
        let textBounds = attributed.boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let drawRect = NSRect(
            x: bounds.maxX - ceil(textBounds.width) - textBounds.origin.x,
            y: bounds.midY - textBounds.height / 2 - textBounds.origin.y,
            width: ceil(textBounds.width),
            height: textBounds.height
        )
        GlassTextReadabilityRenderer.draw(
            attributed,
            in: drawRect,
            options: [.usesLineFragmentOrigin],
            haloColor: textHaloColor,
            haloWidth: textHaloWidth
        )
    }

    private func attributedText(_ visibleText: String, paragraph: NSParagraphStyle) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        return NSAttributedString(string: visibleText, attributes: attributes)
    }

    private func applyLeftFadeMask(in context: CGContext) {
        context.setBlendMode(.destinationIn)
        let fadeEnd = min(bounds.maxX, bounds.minX + max(1, fadeWidth))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let transparent = NSColor.black.withAlphaComponent(0).deviceRGBCGColor
        let opaque = NSColor.black.withAlphaComponent(1).deviceRGBCGColor
        if let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [transparent, opaque] as CFArray,
            locations: [0, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: bounds.minX, y: bounds.midY),
                end: CGPoint(x: fadeEnd, y: bounds.midY),
                options: []
            )
        }
        if fadeEnd < bounds.maxX {
            context.setFillColor(opaque)
            context.fill(CGRect(
                x: fadeEnd,
                y: bounds.minY,
                width: bounds.maxX - fadeEnd,
                height: bounds.height
            ))
        }
    }
}

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

    var textHaloColor: NSColor? {
        didSet { needsDisplay = true }
    }

    var textHaloWidth: CGFloat = 0 {
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
        let attributed = attributedText(paragraph: paragraph)
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
        GlassTextReadabilityRenderer.draw(
            attributed,
            in: drawRect,
            options: [.usesLineFragmentOrigin],
            haloColor: textHaloColor,
            haloWidth: textHaloWidth
        )
    }

    private func attributedText(paragraph: NSParagraphStyle) -> NSAttributedString {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: badgeFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        return NSAttributedString(string: text, attributes: attributes)
    }
}

private extension NSColor {
    var deviceRGBCGColor: CGColor {
        usingColorSpace(.deviceRGB)?.cgColor ?? cgColor
    }
}
