import CoreGraphics
import Foundation

public struct SurfaceDiagnosticSnapshot: Equatable, Sendable {
    public let panelType: String
    public let levelName: String
    public let isVisible: Bool
    public let frame: CGRect?
    public let windowNumber: Int?

    public init(
        panelType: String,
        levelName: String,
        isVisible: Bool,
        frame: CGRect?,
        windowNumber: Int? = nil
    ) {
        self.panelType = panelType
        self.levelName = levelName
        self.isVisible = isVisible
        self.frame = frame
        self.windowNumber = windowNumber
    }
}

public enum ActionPanelSurfaceMetrics {
    public static let usesSystemShadow = false
}

public enum ActionPanelShortcutMetrics {
    public static let bubbleHeight: CGFloat = 18
    public static let bubbleCenterYOffset: CGFloat = 0

    public static func glyphBaselineOffset(for shortcut: String, glyphHeight: CGFloat? = nil) -> CGFloat {
        ShortcutGlyphLayoutResolver.glyphBaselineOffset(for: shortcut, glyphHeight: glyphHeight)
    }
}

public enum ShortcutGlyphLayoutResolver {
    public static func glyphBaselineOffset(for shortcut: String, glyphHeight: CGFloat? = nil) -> CGFloat {
        let heightCompensation = max(0, (glyphHeight ?? 10) - 10) * -0.12
        if shortcut == "↩" {
            return 1.5 + heightCompensation
        }
        return heightCompensation
    }

    public static func glyphDrawOriginY(
        bubbleMidY: CGFloat,
        glyphHeight: CGFloat,
        shortcut: String
    ) -> CGFloat {
        bubbleMidY - glyphHeight / 2 + glyphBaselineOffset(for: shortcut, glyphHeight: glyphHeight)
    }
}

public struct MorphingPanelFrames: Equatable, Sendable {
    public let start: CGRect
    public let horizontalExpanded: CGRect
    public let final: CGRect

    public init(start: CGRect, horizontalExpanded: CGRect, final: CGRect) {
        self.start = start
        self.horizontalExpanded = horizontalExpanded
        self.final = final
    }
}

public enum MorphingPanelFramePlanner {
    public static func frames(
        start: CGRect?,
        screen: CGRect,
        finalSize: CGSize = CGSize(width: 560, height: 252),
        margin: CGFloat = 24
    ) -> MorphingPanelFrames {
        let width = min(finalSize.width, max(220, screen.width - margin * 2))
        let height = min(finalSize.height, max(160, screen.height - margin * 2))
        let fallbackStart = CGRect(
            x: screen.midX - 168 / 2,
            y: screen.minY + 18,
            width: 168,
            height: 40
        )
        let rawStart = start ?? fallbackStart
        let startFrame = clamp(rawStart, inside: screen, horizontalMargin: margin, bottomMargin: 8)
        let targetX = clamp(
            startFrame.midX - width / 2,
            min: screen.minX + margin,
            max: screen.maxX - margin - width
        )
        let targetY = clamp(
            startFrame.minY,
            min: screen.minY + 8,
            max: screen.maxY - margin - height
        )
        let horizontal = CGRect(
            x: targetX,
            y: startFrame.minY,
            width: width,
            height: startFrame.height
        )
        let final = CGRect(
            x: targetX,
            y: targetY,
            width: width,
            height: height
        )
        return MorphingPanelFrames(start: startFrame, horizontalExpanded: horizontal, final: final)
    }

    private static func clamp(
        _ rect: CGRect,
        inside screen: CGRect,
        horizontalMargin: CGFloat,
        bottomMargin: CGFloat
    ) -> CGRect {
        let width = min(rect.width, max(1, screen.width - horizontalMargin * 2))
        let height = min(rect.height, max(1, screen.height - bottomMargin - horizontalMargin))
        return CGRect(
            x: clamp(rect.minX, min: screen.minX + horizontalMargin, max: screen.maxX - horizontalMargin - width),
            y: clamp(rect.minY, min: screen.minY + bottomMargin, max: screen.maxY - horizontalMargin - height),
            width: width,
            height: height
        )
    }

    private static func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minValue), maxValue)
    }
}

public enum ActionPanelSizePlanner {
    public static func size(
        bodyCharacterCount: Int,
        lineBreakCount: Int,
        hasTitle: Bool,
        screen: CGSize,
        scenario: ActionPanelScenario
    ) -> CGSize {
        let width = min(max(420, screen.width * 0.42), min(640, screen.width - 48))
        let estimatedWrappedLines = max(1, Int(ceil(Double(max(bodyCharacterCount, 1)) / 36.0)))
        let lines = max(estimatedWrappedLines, lineBreakCount + 1)
        let textHeight = min(max(CGFloat(lines) * 21 + 24, scenario == .retry ? 70 : 92), screen.height * 0.34)
        let titleHeight: CGFloat = hasTitle ? 24 : 0
        let height = min(max(142, titleHeight + textHeight + 78), min(380, screen.height * 0.48))
        return CGSize(width: width, height: height)
    }
}

public enum ActionPanelScenario: Equatable, Sendable {
    case retry
    case result
}

public enum ActionPanelButtonRole: String, Equatable, Sendable {
    case cancel
    case retry
    case styleSwitcher
    case copy
}

public struct ActionPanelStyleOption: Equatable, Sendable {
    public let selection: TranscriptionStyleSelection
    public let title: String
    public let tooltip: String?

    public init(selection: TranscriptionStyleSelection, title: String, tooltip: String? = nil) {
        self.selection = selection
        self.title = title
        self.tooltip = tooltip
    }
}

public struct ActionPanelButtonLayout: Equatable, Sendable {
    public let order: [ActionPanelButtonRole]
    public let primary: ActionPanelButtonRole
    public let escape: ActionPanelButtonRole
    public let shortcuts: [ActionPanelButtonRole: String]

    public init(
        order: [ActionPanelButtonRole],
        primary: ActionPanelButtonRole,
        escape: ActionPanelButtonRole,
        shortcuts: [ActionPanelButtonRole: String]
    ) {
        self.order = order
        self.primary = primary
        self.escape = escape
        self.shortcuts = shortcuts
    }
}

public enum ActionPanelButtonLayoutPlanner {
    public static func layout(for scenario: ActionPanelScenario) -> ActionPanelButtonLayout {
        switch scenario {
        case .retry:
            return ActionPanelButtonLayout(
                order: [.retry, .cancel],
                primary: .retry,
                escape: .cancel,
                shortcuts: [.retry: "↩", .cancel: "Esc"]
            )
        case .result:
            return ActionPanelButtonLayout(
                order: [.copy, .styleSwitcher, .cancel],
                primary: .copy,
                escape: .cancel,
                shortcuts: [.copy: "↩", .cancel: "Esc"]
            )
        }
    }
}

public enum RestartAppPlanner {
    public static func bundleURL(
        currentBundleURL: URL,
        fallbackApplicationsURL: URL = URL(fileURLWithPath: "/Applications/OmniVoice.app")
    ) -> URL {
        currentBundleURL.pathExtension == "app" ? currentBundleURL : fallbackApplicationsURL
    }
}

public struct ConfigEditorCandidate: Equatable, Sendable {
    public let displayName: String
    public let appBundleNames: [String]
    public let cliNames: [String]

    public init(displayName: String, appBundleNames: [String], cliNames: [String]) {
        self.displayName = displayName
        self.appBundleNames = appBundleNames
        self.cliNames = cliNames
    }
}

public enum ConfigFileOpenMethod: Equatable, Sendable {
    case applicationBundle(URL, displayName: String)
    case command(URL, displayName: String)
    case systemDefault
}

public struct ConfigFileOpenPlan: Equatable, Sendable {
    public let method: ConfigFileOpenMethod

    public init(method: ConfigFileOpenMethod) {
        self.method = method
    }
}

public enum ConfigFileOpenPlanner {
    public static let candidates: [ConfigEditorCandidate] = [
        ConfigEditorCandidate(displayName: "Visual Studio Code", appBundleNames: ["Visual Studio Code.app"], cliNames: ["code"]),
        ConfigEditorCandidate(displayName: "Cursor", appBundleNames: ["Cursor.app"], cliNames: ["cursor"]),
        ConfigEditorCandidate(displayName: "Windsurf", appBundleNames: ["Windsurf.app"], cliNames: ["windsurf"]),
        ConfigEditorCandidate(displayName: "Zed", appBundleNames: ["Zed.app"], cliNames: ["zed"]),
        ConfigEditorCandidate(displayName: "Sublime Text", appBundleNames: ["Sublime Text.app"], cliNames: ["subl"]),
        ConfigEditorCandidate(displayName: "BBEdit", appBundleNames: ["BBEdit.app"], cliNames: ["bbedit"]),
        ConfigEditorCandidate(displayName: "TextMate", appBundleNames: ["TextMate.app"], cliNames: ["mate"]),
        ConfigEditorCandidate(displayName: "Xcode", appBundleNames: ["Xcode.app"], cliNames: ["xed"])
    ]

    public static func plan(
        applicationsDirectories: [URL] = defaultApplicationsDirectories(),
        executableDirectories: [URL] = defaultExecutableDirectories(),
        fileManager: FileManager = .default
    ) -> ConfigFileOpenPlan {
        for candidate in candidates {
            if let bundleURL = findApplicationBundle(
                candidate: candidate,
                directories: applicationsDirectories,
                fileManager: fileManager
            ) {
                return ConfigFileOpenPlan(method: .applicationBundle(bundleURL, displayName: candidate.displayName))
            }
        }
        for candidate in candidates {
            if let commandURL = findCommand(
                candidate: candidate,
                directories: executableDirectories,
                fileManager: fileManager
            ) {
                return ConfigFileOpenPlan(method: .command(commandURL, displayName: candidate.displayName))
            }
        }
        return ConfigFileOpenPlan(method: .systemDefault)
    }

    public static func defaultApplicationsDirectories() -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    public static func defaultExecutableDirectories() -> [URL] {
        [
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/bin", isDirectory: true)
        ]
    }

    private static func findApplicationBundle(
        candidate: ConfigEditorCandidate,
        directories: [URL],
        fileManager: FileManager
    ) -> URL? {
        for directory in directories {
            for bundleName in candidate.appBundleNames {
                let url = directory.appendingPathComponent(bundleName, isDirectory: true)
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                    return url
                }
            }
        }
        return nil
    }

    private static func findCommand(
        candidate: ConfigEditorCandidate,
        directories: [URL],
        fileManager: FileManager
    ) -> URL? {
        for directory in directories {
            for commandName in candidate.cliNames {
                let url = directory.appendingPathComponent(commandName)
                if fileManager.isExecutableFile(atPath: url.path) {
                    return url
                }
            }
        }
        return nil
    }
}
