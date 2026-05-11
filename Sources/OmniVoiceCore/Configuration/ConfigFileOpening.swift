import Foundation

struct ConfigEditorCandidate: Equatable, Sendable {
    let displayName: String
    let appBundleNames: [String]
    let cliNames: [String]
    let lineInvocation: ConfigEditorLineInvocation

    init(
        displayName: String,
        appBundleNames: [String],
        cliNames: [String],
        lineInvocation: ConfigEditorLineInvocation = .plainFile
    ) {
        self.displayName = displayName
        self.appBundleNames = appBundleNames
        self.cliNames = cliNames
        self.lineInvocation = lineInvocation
    }
}

enum ConfigEditorLineInvocation: Equatable, Sendable {
    case gotoFlag
    case zedPathSuffix
    case xedLineFlag
    case plainFile

    var supportsLineNumber: Bool {
        self != .plainFile
    }

    func arguments(fileURL: URL, line: Int, column: Int) -> [String] {
        let safeLine = max(1, line)
        let safeColumn = max(1, column)
        switch self {
        case .gotoFlag:
            return ["--goto", "\(fileURL.path):\(safeLine):\(safeColumn)"]
        case .zedPathSuffix:
            return ["\(fileURL.path):\(safeLine):\(safeColumn)"]
        case .xedLineFlag:
            return ["-l", "\(safeLine)", fileURL.path]
        case .plainFile:
            return [fileURL.path]
        }
    }
}

enum ConfigFileOpenMethod: Equatable, Sendable {
    case applicationBundle(URL, displayName: String)
    case command(URL, displayName: String)
    case systemDefault
}

struct ConfigFileOpenPlan: Equatable, Sendable {
    let method: ConfigFileOpenMethod
    let arguments: [String]

    init(method: ConfigFileOpenMethod, arguments: [String] = []) {
        self.method = method
        self.arguments = arguments
    }
}

enum ConfigFileSection: Equatable, Sendable {
    case root
    case sources
    case modelsAudioLLM
    case modelsTextLLM
    case keywordGroups
    case customStyles
    case systemASR
    case preferences
}

enum ConfigFileLineLocator {
    static func lineNumber(in text: String, section: ConfigFileSection) -> Int {
        switch section {
        case .root:
            return 1
        case .sources:
            return firstLine(matchingKey: "sources", in: text) ?? 1
        case .modelsAudioLLM:
            return firstLine(matchingKey: "audio_llm", in: text)
                ?? firstLine(matchingKey: "models", in: text)
                ?? 1
        case .modelsTextLLM:
            return firstLine(matchingKey: "text_llm", in: text)
                ?? firstLine(matchingKey: "models", in: text)
                ?? 1
        case .keywordGroups:
            return firstLine(matchingKey: "keyword_groups", in: text) ?? 1
        case .customStyles:
            return firstLine(matchingKey: "custom_styles", in: text) ?? 1
        case .systemASR:
            return firstLine(matchingKey: "system_asr", in: text) ?? 1
        case .preferences:
            return firstLine(matchingKey: "preferences", in: text) ?? 1
        }
    }

    private static func firstLine(matchingKey key: String, in text: String) -> Int? {
        let pattern = "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:"
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.range(of: pattern, options: .regularExpression) != nil {
                return index + 1
            }
        }
        return nil
    }
}

enum ConfigFileOpenPlanner {
    static let candidates: [ConfigEditorCandidate] = [
        ConfigEditorCandidate(displayName: "Visual Studio Code", appBundleNames: ["Visual Studio Code.app"], cliNames: ["code"], lineInvocation: .gotoFlag),
        ConfigEditorCandidate(displayName: "Cursor", appBundleNames: ["Cursor.app"], cliNames: ["cursor"], lineInvocation: .gotoFlag),
        ConfigEditorCandidate(displayName: "Windsurf", appBundleNames: ["Windsurf.app"], cliNames: ["windsurf"]),
        ConfigEditorCandidate(displayName: "Zed", appBundleNames: ["Zed.app"], cliNames: ["zed"], lineInvocation: .zedPathSuffix),
        ConfigEditorCandidate(displayName: "Sublime Text", appBundleNames: ["Sublime Text.app"], cliNames: ["subl"]),
        ConfigEditorCandidate(displayName: "BBEdit", appBundleNames: ["BBEdit.app"], cliNames: ["bbedit"]),
        ConfigEditorCandidate(displayName: "TextMate", appBundleNames: ["TextMate.app"], cliNames: ["mate"]),
        ConfigEditorCandidate(displayName: "Xcode", appBundleNames: ["Xcode.app"], cliNames: ["xed"], lineInvocation: .xedLineFlag)
    ]

    static func plan(
        applicationsDirectories: [URL] = defaultApplicationsDirectories(),
        executableDirectories: [URL] = defaultExecutableDirectories(),
        fileManager: FileManager = .default,
        fileURL: URL? = nil,
        line: Int = 1,
        column: Int = 1
    ) -> ConfigFileOpenPlan {
        if let fileURL {
            for candidate in candidates where candidate.lineInvocation.supportsLineNumber {
                if let commandURL = findCommand(
                    candidate: candidate,
                    directories: executableDirectories,
                    fileManager: fileManager
                ) {
                    return ConfigFileOpenPlan(
                        method: .command(commandURL, displayName: candidate.displayName),
                        arguments: candidate.lineInvocation.arguments(fileURL: fileURL, line: line, column: column)
                    )
                }
            }
        }
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
                let arguments = fileURL.map {
                    candidate.lineInvocation.arguments(fileURL: $0, line: line, column: column)
                } ?? []
                return ConfigFileOpenPlan(
                    method: .command(commandURL, displayName: candidate.displayName),
                    arguments: arguments
                )
            }
        }
        return ConfigFileOpenPlan(method: .systemDefault)
    }

    static func defaultApplicationsDirectories() -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    static func defaultExecutableDirectories() -> [URL] {
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
