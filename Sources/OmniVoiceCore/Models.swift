import Foundation
import CoreGraphics

public enum AllowedSpeechModel: String, CaseIterable, Codable, Sendable {
    case mimoV2Omni = "mimo-v2-omni"
    case mimoV25 = "mimo-v2.5"

    public static let defaultModel: AllowedSpeechModel = .mimoV2Omni
    public static let fallbackModel: AllowedSpeechModel = .mimoV25

    public var displayName: String { rawValue }

    public static func filterSpeechModels(from ids: [String]) -> [AllowedSpeechModel] {
        let available = Set(ids.filter { !$0.lowercased().contains("-tts") })
        return Self.allCases.filter { available.contains($0.rawValue) }
    }

    public static func safeSelection(_ rawValue: String?) -> AllowedSpeechModel {
        guard let rawValue, let model = AllowedSpeechModel(rawValue: rawValue) else {
            return defaultModel
        }
        return model
    }
}

public enum LanguagePreference: String, CaseIterable, Codable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-CN"
    case traditionalChinese = "zh-TW"
    case japanese = "ja"
    case korean = "ko"

    public static let defaultLanguage: LanguagePreference = .simplifiedChinese

    public var displayName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁体中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }

    public var instructionName: String {
        switch self {
        case .english: return "English (en)"
        case .simplifiedChinese: return "简体中文（zh-CN）"
        case .traditionalChinese: return "繁体中文（zh-TW）"
        case .japanese: return "日本語（ja）"
        case .korean: return "한국어（ko）"
        }
    }
}

public enum UILanguage: String, CaseIterable, Codable, Sendable {
    case chinese = "zh-Hans"
    case english = "en"

    public static let defaultLanguage: UILanguage = .chinese

    public var displayName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }

    public static func safeSelection(_ rawValue: String?) -> UILanguage {
        guard let rawValue, let language = UILanguage(rawValue: rawValue) else {
            return .defaultLanguage
        }
        return language
    }

    public static func migratedFromLegacyLanguage(_ rawValue: String?) -> UILanguage {
        rawValue == LanguagePreference.english.rawValue ? .english : .chinese
    }
}

public enum TranscriptionStyle: String, CaseIterable, Codable, Sendable {
    case concise
    case verbatim
    case codeFaithful
    case rewrite

    public static let defaultStyle: TranscriptionStyle = .concise
    public static let menuOrder: [TranscriptionStyle] = [.verbatim, .concise, .codeFaithful, .rewrite]

    public var displayName: String {
        switch self {
        case .concise: return "精炼"
        case .verbatim: return "原文"
        case .codeFaithful: return "技术"
        case .rewrite: return "重写"
        }
    }

    public func displayName(in uiLanguage: UILanguage) -> String {
        switch uiLanguage {
        case .chinese:
            return displayName
        case .english:
            switch self {
            case .concise: return "Concise"
            case .verbatim: return "Verbatim"
            case .codeFaithful: return "Technical"
            case .rewrite: return "Rewrite"
            }
        }
    }
}

public struct CustomTranscriptionStyle: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let displayNameZH: String?
    public let description: String?
    public let descriptionZH: String?
    public let prompt: String

    public init(
        id: String,
        displayName: String,
        displayNameZH: String? = nil,
        description: String? = nil,
        descriptionZH: String? = nil,
        prompt: String
    ) {
        self.id = id
        self.displayName = displayName
        self.displayNameZH = displayNameZH?.nilIfBlank
        self.description = description?.nilIfBlank
        self.descriptionZH = descriptionZH?.nilIfBlank
        self.prompt = prompt
    }

    public func localizedName(in uiLanguage: UILanguage) -> String {
        switch uiLanguage {
        case .chinese:
            return displayNameZH ?? displayName
        case .english:
            return displayName
        }
    }

    public func localizedDescription(in uiLanguage: UILanguage) -> String? {
        switch uiLanguage {
        case .chinese:
            return descriptionZH ?? description
        case .english:
            return description
        }
    }
}

public struct TranscriptionStyleSelection: RawRepresentable, Codable, Hashable, Sendable {
    public static let customPrefix = "custom:"
    public static let defaultSelection = TranscriptionStyleSelection.builtIn(.concise)

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.nilIfBlank ?? TranscriptionStyle.defaultStyle.rawValue
    }

    public static func builtIn(_ style: TranscriptionStyle) -> TranscriptionStyleSelection {
        TranscriptionStyleSelection(rawValue: style.rawValue)
    }

    public static func custom(_ id: String) -> TranscriptionStyleSelection {
        TranscriptionStyleSelection(rawValue: "\(customPrefix)\(id)")
    }

    public var builtInStyle: TranscriptionStyle? {
        TranscriptionStyle(rawValue: rawValue)
    }

    public var customStyleID: String? {
        guard rawValue.hasPrefix(Self.customPrefix) else { return nil }
        return String(rawValue.dropFirst(Self.customPrefix.count)).nilIfBlank
    }
}

public struct TranscriptionStyleDescriptor: Equatable, Sendable {
    public let selection: TranscriptionStyleSelection
    public let displayName: String
    public let displayNameZH: String?
    public let tooltip: String?
    public let tooltipZH: String?
    public let prompt: String?
    public let builtInStyle: TranscriptionStyle?

    public init(
        selection: TranscriptionStyleSelection,
        displayName: String,
        displayNameZH: String? = nil,
        tooltip: String? = nil,
        tooltipZH: String? = nil,
        prompt: String? = nil,
        builtInStyle: TranscriptionStyle? = nil
    ) {
        self.selection = selection
        self.displayName = displayName
        self.displayNameZH = displayNameZH?.nilIfBlank
        self.tooltip = tooltip?.nilIfBlank
        self.tooltipZH = tooltipZH?.nilIfBlank
        self.prompt = prompt?.nilIfBlank
        self.builtInStyle = builtInStyle
    }

    public var isCustom: Bool {
        builtInStyle == nil
    }

    public func localizedName(in uiLanguage: UILanguage) -> String {
        switch uiLanguage {
        case .chinese:
            return displayNameZH ?? displayName
        case .english:
            return displayName
        }
    }

    public func localizedTooltip(in uiLanguage: UILanguage) -> String? {
        switch uiLanguage {
        case .chinese:
            return tooltipZH ?? tooltip
        case .english:
            return tooltip
        }
    }
}

public enum TranscriptionStyleResolver {
    public static func builtInDescriptor(_ style: TranscriptionStyle) -> TranscriptionStyleDescriptor {
        TranscriptionStyleDescriptor(
            selection: .builtIn(style),
            displayName: style.displayName(in: .english),
            displayNameZH: style.displayName(in: .chinese),
            builtInStyle: style
        )
    }

    public static func customDescriptor(_ style: CustomTranscriptionStyle) -> TranscriptionStyleDescriptor {
        TranscriptionStyleDescriptor(
            selection: .custom(style.id),
            displayName: style.displayName,
            displayNameZH: style.displayNameZH,
            tooltip: style.description,
            tooltipZH: style.descriptionZH,
            prompt: style.prompt,
            builtInStyle: nil
        )
    }

    public static func menuDescriptors(customStyles: [CustomTranscriptionStyle]) -> [TranscriptionStyleDescriptor] {
        TranscriptionStyle.menuOrder.map(builtInDescriptor)
            + customStyles.map(customDescriptor)
    }

    public static func resolve(
        selection: TranscriptionStyleSelection,
        customStyles: [CustomTranscriptionStyle]
    ) -> TranscriptionStyleDescriptor {
        if let customID = selection.customStyleID,
           let custom = customStyles.first(where: { $0.id == customID }) {
            return customDescriptor(custom)
        }
        if let builtIn = selection.builtInStyle {
            return builtInDescriptor(builtIn)
        }
        return builtInDescriptor(.defaultStyle)
    }
}

public enum TriggerKind: String, Codable, Sendable {
    case fnGlobe
    case functionKey
    case modifier
    case capsLock
}

public enum TriggerLocation: String, Codable, Sendable {
    case any
    case left
    case right
}

public struct TriggerKey: Codable, Equatable, Hashable, Sendable {
    public let identifier: String
    public let displayLabel: String
    public let keyCode: Int?
    public let modifierFlagsRawValue: UInt64
    public let location: TriggerLocation
    public let kind: TriggerKind

    public init(
        identifier: String,
        displayLabel: String,
        keyCode: Int?,
        modifierFlagsRawValue: UInt64 = 0,
        location: TriggerLocation = .any,
        kind: TriggerKind
    ) {
        self.identifier = identifier
        self.displayLabel = displayLabel
        self.keyCode = keyCode
        self.modifierFlagsRawValue = modifierFlagsRawValue
        self.location = location
        self.kind = kind
    }

    public static let fnGlobe = TriggerKey(
        identifier: "fn-globe",
        displayLabel: "Fn/Globe",
        keyCode: nil,
        modifierFlagsRawValue: CGEventFlags.maskSecondaryFn.rawValue,
        location: .any,
        kind: .fnGlobe
    )

    public static let leftControl = TriggerKey(
        identifier: "modifier-left-control",
        displayLabel: "Left Control",
        keyCode: 59,
        modifierFlagsRawValue: CGEventFlags.maskControl.rawValue,
        location: .left,
        kind: .modifier
    )

    public static let defaultTrigger = fnGlobe

    public static let functionKeys: [TriggerKey] = [
        ("F1", 122), ("F2", 120), ("F3", 99), ("F4", 118), ("F5", 96),
        ("F6", 97), ("F7", 98), ("F8", 100), ("F9", 101), ("F10", 109),
        ("F11", 103), ("F12", 111)
    ].map { label, code in
        TriggerKey(
            identifier: "function-\(label.lowercased())",
            displayLabel: label,
            keyCode: code,
            kind: .functionKey
        )
    }

    public static let modifierKeys: [TriggerKey] = [
        TriggerKey(
            identifier: "modifier-left-shift",
            displayLabel: "Left Shift",
            keyCode: 56,
            modifierFlagsRawValue: CGEventFlags.maskShift.rawValue,
            location: .left,
            kind: .modifier
        ),
        TriggerKey(
            identifier: "modifier-right-shift",
            displayLabel: "Right Shift",
            keyCode: 60,
            modifierFlagsRawValue: CGEventFlags.maskShift.rawValue,
            location: .right,
            kind: .modifier
        ),
        leftControl,
        TriggerKey(
            identifier: "modifier-right-control",
            displayLabel: "Right Control",
            keyCode: 62,
            modifierFlagsRawValue: CGEventFlags.maskControl.rawValue,
            location: .right,
            kind: .modifier
        ),
        TriggerKey(
            identifier: "modifier-left-option",
            displayLabel: "Left Option",
            keyCode: 58,
            modifierFlagsRawValue: CGEventFlags.maskAlternate.rawValue,
            location: .left,
            kind: .modifier
        ),
        TriggerKey(
            identifier: "modifier-right-option",
            displayLabel: "Right Option",
            keyCode: 61,
            modifierFlagsRawValue: CGEventFlags.maskAlternate.rawValue,
            location: .right,
            kind: .modifier
        ),
        TriggerKey(
            identifier: "modifier-left-command",
            displayLabel: "Left Command",
            keyCode: 55,
            modifierFlagsRawValue: CGEventFlags.maskCommand.rawValue,
            location: .left,
            kind: .modifier
        ),
        TriggerKey(
            identifier: "modifier-right-command",
            displayLabel: "Right Command",
            keyCode: 54,
            modifierFlagsRawValue: CGEventFlags.maskCommand.rawValue,
            location: .right,
            kind: .modifier
        )
    ]

    public static let capsLock = TriggerKey(
        identifier: "caps-lock",
        displayLabel: "Caps Lock",
        keyCode: 57,
        modifierFlagsRawValue: CGEventFlags.maskAlphaShift.rawValue,
        location: .any,
        kind: .capsLock
    )

    public static var allCandidates: [TriggerKey] {
        [fnGlobe] + functionKeys + modifierKeys + [capsLock]
    }

    public static func candidate(identifier: String?) -> TriggerKey {
        guard let identifier,
              let candidate = allCandidates.first(where: { $0.identifier == identifier }) else {
            return .defaultTrigger
        }
        return candidate
    }

    public static func captureCandidate(keyCode: Int?, includesFunctionModifier: Bool = false) -> TriggerKey? {
        if includesFunctionModifier {
            return .fnGlobe
        }
        guard let keyCode else { return nil }
        if let functionKey = functionKeys.first(where: { $0.keyCode == keyCode }) {
            return functionKey
        }
        if let modifierKey = modifierKeys.first(where: { $0.keyCode == keyCode }) {
            return modifierKey
        }
        if capsLock.keyCode == keyCode {
            return .capsLock
        }
        return nil
    }
}

public enum MaxRecordingDuration: Int, CaseIterable, Codable, Sendable {
    case seconds15 = 15
    case seconds30 = 30
    case seconds60 = 60
    case seconds120 = 120
    case seconds300 = 300

    public static let defaultDuration: MaxRecordingDuration = .seconds60

    public var displayName: String { "\(rawValue)s" }

    public static func safeSelection(_ seconds: Int) -> MaxRecordingDuration {
        MaxRecordingDuration(rawValue: seconds) ?? .defaultDuration
    }
}

public enum MinRecordingDuration: Int, CaseIterable, Codable, Sendable {
    case milliseconds300 = 300
    case milliseconds500 = 500
    case milliseconds800 = 800
    case seconds1 = 1_000
    case seconds2 = 2_000
    case seconds3 = 3_000

    public static let defaultDuration: MinRecordingDuration = .milliseconds500

    public var seconds: Double {
        Double(rawValue) / 1_000
    }

    public var displayName: String {
        switch self {
        case .milliseconds300: return "300ms"
        case .milliseconds500: return "500ms"
        case .milliseconds800: return "800ms"
        case .seconds1: return "1s"
        case .seconds2: return "2s"
        case .seconds3: return "3s"
        }
    }

    public static func safeSelection(_ milliseconds: Int) -> MinRecordingDuration {
        MinRecordingDuration(rawValue: milliseconds) ?? .defaultDuration
    }
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
    public let shadowAlpha: CGFloat
    public let warning: Bool
}

public enum GlassReadabilityResolver {
    public static func resolve(
        appearance: GlassBackgroundAppearance,
        status: HUDStatusTone
    ) -> GlassReadabilityStyle {
        switch status {
        case .normal:
            return GlassReadabilityStyle(
                textTone: .light,
                scrimTone: .dark,
                scrimAlpha: appearance == .light ? 0.18 : 0.24,
                tintAlpha: 0.16,
                shadowAlpha: 0.34,
                warning: false
            )
        case .warning:
            return GlassReadabilityStyle(
                textTone: .light,
                scrimTone: .dark,
                scrimAlpha: appearance == .light ? 0.24 : 0.30,
                tintAlpha: 0.22,
                shadowAlpha: 0.36,
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
            return .darkCapsule
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

public struct RecordingValidationResult: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case valid
        case tooShort
        case tooQuiet
    }

    public let status: Status
    public let durationSeconds: Double
    public let overallRMS: Float

    public init(status: Status, durationSeconds: Double, overallRMS: Float) {
        self.status = status
        self.durationSeconds = durationSeconds
        self.overallRMS = overallRMS
    }
}

public enum RecordingValidator {
    public static let minimumDurationSeconds = MinRecordingDuration.defaultDuration.seconds
    public static let minimumEffectiveRMS: Float = 0.008

    public static func validate(
        durationSeconds: Double,
        overallRMS: Float,
        minimumDurationSeconds: Double = minimumDurationSeconds
    ) -> RecordingValidationResult {
        if durationSeconds < minimumDurationSeconds {
            return RecordingValidationResult(status: .tooShort, durationSeconds: durationSeconds, overallRMS: overallRMS)
        }
        if overallRMS < minimumEffectiveRMS {
            return RecordingValidationResult(status: .tooQuiet, durationSeconds: durationSeconds, overallRMS: overallRMS)
        }
        return RecordingValidationResult(status: .valid, durationSeconds: durationSeconds, overallRMS: overallRMS)
    }
}
