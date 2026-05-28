import Foundation

public struct ExternalASRPluginRegistry {
    private let pluginRoots: [URL]
    private let fileManager: FileManager

    public init(
        pluginRoots: [URL] = [Self.defaultPluginRoot],
        fileManager: FileManager = .default
    ) {
        self.pluginRoots = pluginRoots
        self.fileManager = fileManager
    }

    public static var defaultPluginRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/OmniVoice/Plugins", isDirectory: true)
    }

    public func discoverPlugins() -> [ExternalASRPlugin] {
        pluginRoots.flatMap(discoverPlugins(in:))
            .sorted {
                let nameOrder = $0.displayName.localizedStandardCompare($1.displayName)
                if nameOrder == .orderedSame {
                    return $0.id.localizedStandardCompare($1.id) == .orderedAscending
                }
                return nameOrder == .orderedAscending
            }
    }

    private func discoverPlugins(in root: URL) -> [ExternalASRPlugin] {
        guard let children = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return children.compactMap { pluginDirectory in
            guard isDirectory(pluginDirectory) else { return nil }
            return ExternalASRPluginManifest.load(
                from: pluginDirectory.appendingPathComponent("plugin.json"),
                pluginDirectoryURL: pluginDirectory,
                fileManager: fileManager
            )
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
