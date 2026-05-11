import AppKit

enum SurfaceThemeTokens {
    static func capsuleFillColor(surface: HUDResolvedSurface, status: HUDStatusTone) -> NSColor? {
        switch (surface, status) {
        case (.darkCapsule, .normal):
            return NSColor(calibratedRed: 0.035, green: 0.039, blue: 0.047, alpha: 0.97)
        case (.darkCapsule, .warning):
            return NSColor(calibratedRed: 0.240, green: 0.115, blue: 0.055, alpha: 0.98)
        case (.lightCapsule, .normal):
            return NSColor(calibratedRed: 0.985, green: 0.977, blue: 0.948, alpha: 0.98)
        case (.lightCapsule, .warning):
            return NSColor(calibratedRed: 1.0, green: 0.895, blue: 0.770, alpha: 0.98)
        case (.fallbackGlass, .normal):
            return NSColor(calibratedWhite: 1.0, alpha: 0.46)
        case (.fallbackGlass, .warning):
            return NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.56, alpha: 0.58)
        case (.nativeGlass, _):
            return nil
        }
    }

    static func capsuleHighlightColor(status: HUDStatusTone) -> NSColor {
        NSColor.white.withAlphaComponent(status == .warning ? 0.085 : 0.050)
    }

    static func actionPanelFillColors(surface: HUDResolvedSurface, status: HUDStatusTone) -> [NSColor]? {
        switch (surface, status) {
        case (.darkCapsule, .normal):
            return [
                NSColor(calibratedRed: 0.050, green: 0.056, blue: 0.068, alpha: 0.99),
                NSColor(calibratedRed: 0.020, green: 0.023, blue: 0.030, alpha: 0.99)
            ]
        case (.darkCapsule, .warning):
            return [
                NSColor(calibratedRed: 0.270, green: 0.135, blue: 0.072, alpha: 0.99),
                NSColor(calibratedRed: 0.135, green: 0.060, blue: 0.032, alpha: 0.99)
            ]
        case (.lightCapsule, .normal):
            return [
                NSColor(calibratedRed: 0.988, green: 0.978, blue: 0.952, alpha: 0.985),
                NSColor(calibratedRed: 0.950, green: 0.940, blue: 0.915, alpha: 0.970)
            ]
        case (.lightCapsule, .warning):
            return [
                NSColor(calibratedRed: 1.0, green: 0.895, blue: 0.765, alpha: 0.985),
                NSColor(calibratedRed: 0.970, green: 0.790, blue: 0.585, alpha: 0.965)
            ]
        case (.fallbackGlass, .normal):
            return [
                NSColor(calibratedWhite: 1.0, alpha: 0.50),
                NSColor(calibratedWhite: 0.92, alpha: 0.36)
            ]
        case (.fallbackGlass, .warning):
            return [
                NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.68, alpha: 0.58),
                NSColor(calibratedRed: 0.95, green: 0.66, blue: 0.44, alpha: 0.42)
            ]
        case (.nativeGlass, _):
            return nil
        }
    }

    static func innerStrokeColor(status: HUDStatusTone) -> NSColor {
        NSColor.white.withAlphaComponent(status == .warning ? 0.055 : 0.045)
    }

    static func surfaceStrokeColor(
        role: SurfaceDepthRole,
        surface: HUDResolvedSurface,
        status: HUDStatusTone
    ) -> NSColor {
        switch surface {
        case .darkCapsule:
            switch role {
            case .hud:
                return NSColor.white.withAlphaComponent(status == .warning ? 0.22 : 0.15)
            case .actionPanel:
                return NSColor.white.withAlphaComponent(status == .warning ? 0.23 : 0.16)
            }
        case .lightCapsule:
            switch role {
            case .hud:
                return NSColor.black.withAlphaComponent(status == .warning ? 0.17 : 0.11)
            case .actionPanel:
                return NSColor.black.withAlphaComponent(status == .warning ? 0.18 : 0.12)
            }
        case .nativeGlass:
            return NSColor.white.withAlphaComponent(status == .warning ? 0.34 : 0.28)
        case .fallbackGlass:
            switch role {
            case .hud:
                return NSColor.black.withAlphaComponent(status == .warning ? 0.20 : 0.13)
            case .actionPanel:
                return NSColor.black.withAlphaComponent(status == .warning ? 0.24 : 0.14)
            }
        }
    }

    static func actionPanelButtonPalette(
        visualRole: ThemedPanelButton.VisualRole,
        surface: HUDResolvedSurface,
        status: HUDStatusTone,
        highlighted: Bool,
        glassTextTone: HUDTextTone
    ) -> (fill: NSColor, stroke: NSColor, text: NSColor) {
        let pressed: CGFloat = highlighted ? 0.12 : 0
        if surface == .nativeGlass {
            let text = textColor(for: glassTextTone)
            switch visualRole {
            case .primary:
                return (
                    status == .warning
                        ? NSColor(calibratedRed: 0.90 - pressed, green: 0.40, blue: 0.14, alpha: 0.88)
                        : NSColor(calibratedRed: 0.12, green: 0.43 - pressed, blue: 0.90 - pressed, alpha: 0.82),
                    text.withAlphaComponent(0.14),
                    .white
                )
            case .secondary:
                return (
                    NSColor.black.withAlphaComponent(highlighted ? 0.20 : 0.13),
                    NSColor.white.withAlphaComponent(0.22),
                    text.withAlphaComponent(0.94)
                )
            }
        }

        let lightSurface = surface == .lightCapsule || surface == .fallbackGlass
        switch (visualRole, lightSurface, status) {
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
                NSColor.white.withAlphaComponent(highlighted ? 0.18 : 0.11),
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
                NSColor.black.withAlphaComponent(highlighted ? 0.12 : 0.07),
                NSColor.black.withAlphaComponent(0.12),
                NSColor(calibratedWhite: 0.10, alpha: 0.92)
            )
        }
    }
}
