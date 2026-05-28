import Foundation

public struct ExternalASRPlugin: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let version: String
    public let pluginDirectoryURL: URL
    public let executableURL: URL
    public let supportsStreaming: Bool
    public let supportsSetup: Bool

    public init(
        id: String,
        displayName: String,
        version: String,
        pluginDirectoryURL: URL,
        executableURL: URL,
        supportsStreaming: Bool,
        supportsSetup: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.pluginDirectoryURL = pluginDirectoryURL
        self.executableURL = executableURL
        self.supportsStreaming = supportsStreaming
        self.supportsSetup = supportsSetup
    }
}

struct ExternalASRPluginManifest: Decodable {
    let id: String
    let name: String
    let version: String
    let type: String
    let entry: String
    let `protocol`: String
    let capabilities: Capabilities?

    struct Capabilities: Decodable {
        let streaming: Bool?
        let setup: Bool?
    }

    static let providerType = "asr_provider"
    static let protocolVersion = "omnivoice-asr-jsonl-v1"

    func resolvedPlugin(
        pluginDirectoryURL: URL,
        fileManager: FileManager = .default
    ) -> ExternalASRPlugin? {
        guard Self.isValidID(id),
              type == Self.providerType,
              `protocol` == Self.protocolVersion,
              let displayName = name.nilIfBlank,
              let version = version.nilIfBlank,
              let executableURL = Self.resolveEntry(
                entry,
                pluginDirectoryURL: pluginDirectoryURL,
                fileManager: fileManager
              ) else {
            return nil
        }
        return ExternalASRPlugin(
            id: id,
            displayName: displayName,
            version: version,
            pluginDirectoryURL: pluginDirectoryURL.standardizedFileURL,
            executableURL: executableURL,
            supportsStreaming: capabilities?.streaming ?? false,
            supportsSetup: capabilities?.setup ?? false
        )
    }

    static func load(
        from manifestURL: URL,
        pluginDirectoryURL: URL,
        fileManager: FileManager = .default
    ) -> ExternalASRPlugin? {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(ExternalASRPluginManifest.self, from: data) else {
            return nil
        }
        return manifest.resolvedPlugin(pluginDirectoryURL: pluginDirectoryURL, fileManager: fileManager)
    }

    static func isValidID(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil
    }

    private static func resolveEntry(
        _ entry: String,
        pluginDirectoryURL: URL,
        fileManager: FileManager
    ) -> URL? {
        guard let entry = entry.nilIfBlank,
              !entry.hasPrefix("/") else {
            return nil
        }
        let components = entry.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty,
              !components.contains(""),
              !components.contains("."),
              !components.contains("..") else {
            return nil
        }
        let pluginDirectory = pluginDirectoryURL.standardizedFileURL
        let executableURL = pluginDirectory.appendingPathComponent(entry).standardizedFileURL
        guard executableURL.path.hasPrefix(pluginDirectory.path + "/"),
              fileManager.fileExists(atPath: executableURL.path) else {
            return nil
        }
        return executableURL
    }
}
