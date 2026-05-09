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
