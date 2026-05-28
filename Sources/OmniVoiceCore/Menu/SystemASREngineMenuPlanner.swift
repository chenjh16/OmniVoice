import Foundation

struct SystemASREngineMenuEntry: Equatable {
    enum Selection: Equatable {
        case builtIn(SystemASREngine)
        case externalASRProvider(id: String)
    }

    let title: String
    let selection: Selection
    let isSelected: Bool
    let isEnabled: Bool
}

final class ExternalASRProviderMenuSelection: NSObject {
    let providerID: String

    init(providerID: String) {
        self.providerID = providerID
    }
}

enum SystemASREngineMenuPlanner {
    static func entries(
        installedPlugins: [ExternalASRPlugin],
        selectedEngine: SystemASREngine,
        selectedExternalProviderID: String?,
        speechAnalyzerAvailable: Bool,
        uiLanguage: UILanguage
    ) -> [SystemASREngineMenuEntry] {
        let builtInEntries = SystemASREngine.builtInMenuCases.map { engine in
            SystemASREngineMenuEntry(
                title: engine.displayName(in: uiLanguage),
                selection: .builtIn(engine),
                isSelected: engine == selectedEngine,
                isEnabled: engine != .speechAnalyzer || speechAnalyzerAvailable
            )
        }

        let pluginEntries = installedPlugins.map { plugin in
            SystemASREngineMenuEntry(
                title: plugin.displayName,
                selection: .externalASRProvider(id: plugin.id),
                isSelected: selectedEngine == .externalASR && plugin.id == selectedExternalProviderID,
                isEnabled: true
            )
        }

        return builtInEntries + pluginEntries
    }
}

enum ExternalASRSelectionPlanner {
    static func settings(
        selectingProviderID providerID: String,
        installedPlugins: [ExternalASRPlugin],
        current: SystemASRSettings
    ) -> SystemASRSettings? {
        guard installedPlugins.contains(where: { $0.id == providerID }) else { return nil }
        return SystemASRSettings(
            engine: .externalASR,
            keywordHintsEnabled: current.keywordHintsEnabled,
            externalASR: ExternalASRSettings(providerID: providerID)
        )
    }
}
