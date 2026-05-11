import Foundation
import CoreGraphics

public enum HUDSurfaceMetrics {
    public static let usesSystemShadow = false
}

public enum HUDVisualStyle: String, CaseIterable, Codable, Sendable {
    case automatic
    case darkCapsule
    case lightCapsule
    case liquidGlass

    public static let defaultStyle: HUDVisualStyle = .automatic

    public func displayName(in uiLanguage: UILanguage) -> String {
        switch uiLanguage {
        case .chinese:
            switch self {
            case .automatic: return "自动"
            case .darkCapsule: return "深色胶囊"
            case .lightCapsule: return "浅色胶囊"
            case .liquidGlass: return "液态玻璃"
            }
        case .english:
            switch self {
            case .automatic: return "Automatic"
            case .darkCapsule: return "Dark Capsule"
            case .lightCapsule: return "Light Capsule"
            case .liquidGlass: return "Liquid Glass"
            }
        }
    }

    public static func safeSelection(_ rawValue: String?) -> HUDVisualStyle {
        guard let rawValue else {
            return .defaultStyle
        }
        if rawValue == "glass" {
            return .lightCapsule
        }
        guard let style = HUDVisualStyle(rawValue: rawValue) else {
            return .defaultStyle
        }
        return style
    }
}

public enum HUDVisualStyleAvailability {
    public static func isLiquidGlassAvailable(
        operatingSystemMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        nativeGlassClassAvailable: Bool = NSClassFromString("NSGlassEffectView") != nil
    ) -> Bool {
        operatingSystemMajorVersion >= 26 && nativeGlassClassAvailable
    }

    public static func availableStyles(
        operatingSystemMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        nativeGlassClassAvailable: Bool = NSClassFromString("NSGlassEffectView") != nil
    ) -> [HUDVisualStyle] {
        var styles: [HUDVisualStyle] = [.automatic, .darkCapsule, .lightCapsule]
        if isLiquidGlassAvailable(
            operatingSystemMajorVersion: operatingSystemMajorVersion,
            nativeGlassClassAvailable: nativeGlassClassAvailable
        ) {
            styles.append(.liquidGlass)
        }
        return styles
    }

    public static func sanitizedSelection(
        _ style: HUDVisualStyle,
        operatingSystemMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        nativeGlassClassAvailable: Bool = NSClassFromString("NSGlassEffectView") != nil
    ) -> HUDVisualStyle {
        if style == .liquidGlass,
           !isLiquidGlassAvailable(
                operatingSystemMajorVersion: operatingSystemMajorVersion,
                nativeGlassClassAvailable: nativeGlassClassAvailable
           ) {
            return .lightCapsule
        }
        return style
    }
}

public enum HUDMessageDuration: Int, CaseIterable, Codable, Sendable {
    case seconds3 = 3
    case seconds5 = 5
    case seconds8 = 8
    case seconds12 = 12

    public static let defaultDuration: HUDMessageDuration = .seconds3

    public var seconds: TimeInterval {
        TimeInterval(rawValue)
    }

    public var displayName: String {
        "\(rawValue)s"
    }

    public static func safeSelection(_ rawValue: Int) -> HUDMessageDuration {
        HUDMessageDuration(rawValue: rawValue) ?? .defaultDuration
    }
}

public enum HUDRevealDelay: Int, CaseIterable, Codable, Sendable {
    case milliseconds100 = 100
    case milliseconds200 = 200
    case milliseconds300 = 300
    case milliseconds400 = 400
    case milliseconds500 = 500

    public static let defaultDelay: HUDRevealDelay = .milliseconds100

    public var seconds: TimeInterval {
        TimeInterval(rawValue) / 1_000
    }

    public func displayName(in uiLanguage: UILanguage) -> String {
        switch uiLanguage {
        case .chinese:
            switch self {
            case .milliseconds100: return "100ms · 极快"
            case .milliseconds200: return "200ms · 快速（推荐）"
            case .milliseconds300: return "300ms · 平衡"
            case .milliseconds400: return "400ms · 稳妥"
            case .milliseconds500: return "500ms · 最稳"
            }
        case .english:
            switch self {
            case .milliseconds100: return "100ms · Very Fast"
            case .milliseconds200: return "200ms · Fast (Recommended)"
            case .milliseconds300: return "300ms · Balanced"
            case .milliseconds400: return "400ms · Conservative"
            case .milliseconds500: return "500ms · Most Conservative"
            }
        }
    }

    public static func safeSelection(_ rawValue: Int) -> HUDRevealDelay {
        HUDRevealDelay(rawValue: rawValue) ?? .defaultDelay
    }
}

public enum HUDResolvedSurface: Equatable, Sendable {
    case darkCapsule
    case lightCapsule
    case nativeGlass
    case fallbackGlass
}

public enum HUDStatusTone: Equatable, Sendable {
    case normal
    case warning
}

public enum HUDTextTone: Equatable, Sendable {
    case light
    case dark
}

public enum GlassBackgroundAppearance: Equatable, Sendable {
    case light
    case dark
}

public struct HUDPalette: Equatable, Sendable {
    public let textTone: HUDTextTone
    public let warning: Bool
    public let highContrastGlass: Bool
}

public struct GlassReadabilityStyle: Equatable, Sendable {
    public let textTone: HUDTextTone
    public let scrimTone: HUDTextTone
    public let scrimAlpha: CGFloat
    public let tintAlpha: CGFloat
    public let materialAlpha: CGFloat
    public let shadowAlpha: CGFloat
    public let haloAlpha: CGFloat
    public let haloWidth: CGFloat
    public let warning: Bool
}

public enum GlassSurfaceRole: Equatable, Sendable {
    case hud
    case actionPanel
}

public enum GlassReadabilityResolver {
    public static func resolve(
        appearance: GlassBackgroundAppearance,
        status: HUDStatusTone,
        role: GlassSurfaceRole = .hud
    ) -> GlassReadabilityStyle {
        switch status {
        case .normal:
            if role == .actionPanel {
                return GlassReadabilityStyle(
                    textTone: .light,
                    scrimTone: .dark,
                    scrimAlpha: appearance == .light ? 0.28 : 0.18,
                    tintAlpha: appearance == .light ? 0.12 : 0.07,
                    materialAlpha: 1,
                    shadowAlpha: 0.18,
                    haloAlpha: 0.38,
                    haloWidth: 4.1,
                    warning: false
                )
            }
            return GlassReadabilityStyle(
                textTone: .light,
                scrimTone: .dark,
                scrimAlpha: appearance == .light ? 0.14 : 0.075,
                tintAlpha: appearance == .light ? 0.34 : 0.20,
                materialAlpha: 1,
                shadowAlpha: 0.10,
                haloAlpha: 0.24,
                haloWidth: 3.2,
                warning: false
            )
        case .warning:
            if role == .actionPanel {
                return GlassReadabilityStyle(
                    textTone: .light,
                    scrimTone: .dark,
                    scrimAlpha: 0.080,
                    tintAlpha: 0.11,
                    materialAlpha: 1,
                    shadowAlpha: 0.15,
                    haloAlpha: 0.31,
                    haloWidth: 3.65,
                    warning: true
                )
            }
            return GlassReadabilityStyle(
                textTone: .light,
                scrimTone: .dark,
                scrimAlpha: 0.18,
                tintAlpha: 0.25,
                materialAlpha: 1,
                shadowAlpha: 0.12,
                haloAlpha: 0.26,
                haloWidth: 3.4,
                warning: true
            )
        }
    }
}

public enum SurfaceContentHosting: Equatable, Sendable {
    case originalContainer
}

public enum SurfaceHostingPolicy {
    public static func contentHosting(for surface: HUDResolvedSurface) -> SurfaceContentHosting {
        .originalContainer
    }
}

public enum ActionPanelContentTransparencyPolicy {
    public static let scrollViewDrawsBackground = false
    public static let clipViewDrawsBackground = false
    public static let textViewDrawsBackground = false
}

public enum HUDPaletteResolver {
    public static func resolve(surface: HUDResolvedSurface, status: HUDStatusTone) -> HUDPalette {
        let lightSurface = surface == .lightCapsule || surface == .fallbackGlass
        let glass = surface == .nativeGlass || surface == .fallbackGlass
        return HUDPalette(
            textTone: lightSurface ? .dark : .light,
            warning: status == .warning,
            highContrastGlass: glass
        )
    }
}

public enum HUDSurfaceResolver {
    public static func resolve(
        preference: HUDVisualStyle,
        systemAppearance: GlassBackgroundAppearance = .dark,
        operatingSystemMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
        nativeGlassClassAvailable: Bool = NSClassFromString("NSGlassEffectView") != nil
    ) -> HUDResolvedSurface {
        switch preference {
        case .darkCapsule:
            return .darkCapsule
        case .lightCapsule:
            return .lightCapsule
        case .liquidGlass:
            return HUDVisualStyleAvailability.isLiquidGlassAvailable(
                operatingSystemMajorVersion: operatingSystemMajorVersion,
                nativeGlassClassAvailable: nativeGlassClassAvailable
            ) ? .nativeGlass : .lightCapsule
        case .automatic:
            return systemAppearance == .dark ? .darkCapsule : .lightCapsule
        }
    }
}

public struct WaveformMotion: Equatable, Sendable {
    public let active: Bool
    public let phaseStep: CGFloat
    public let amplitudeFloor: CGFloat
}

public enum WaveformMotionResolver {
    public static let idleThreshold: CGFloat = 0.055
    public static let speechThreshold: CGFloat = 0.13
    public static let releaseSeconds: Double = 0.22

    public static func resolve(level: CGFloat, impulse: CGFloat, secondsSinceSpeech: Double?) -> WaveformMotion {
        let normalizedLevel = min(max(level, 0), 1)
        let attackActive = impulse > 0.12
        let speechActive = normalizedLevel >= speechThreshold || attackActive
        let recentlyActive = secondsSinceSpeech.map { $0 <= releaseSeconds } ?? false
        let active = speechActive || recentlyActive
        if active {
            return WaveformMotion(
                active: true,
                phaseStep: 0.15 + normalizedLevel * 0.18 + min(max(impulse, 0), 1) * 0.10,
                amplitudeFloor: 1.7
            )
        }
        let idleLevel = normalizedLevel < idleThreshold ? normalizedLevel : idleThreshold
        return WaveformMotion(
            active: false,
            phaseStep: 0.045 + idleLevel * 0.16,
            amplitudeFloor: 0.9
        )
    }
}
