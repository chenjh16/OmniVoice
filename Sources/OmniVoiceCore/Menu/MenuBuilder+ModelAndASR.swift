import AppKit
import Foundation

@MainActor
extension MenuBuilder {
    func modelConfigurationMenu() -> NSMenu {
        let menu = NSMenu(title: coordinator.strings.modelConfiguration)
        for mode in TranscriptionPipelineMode.allCases {
            let menuItem = item(
                title: mode.displayName(in: coordinator.settings.uiLanguage),
                action: #selector(AppCoordinator.selectPipelineMode(_:))
            )
            menuItem.representedObject = mode.rawValue
            menuItem.state = mode == coordinator.settings.pipelineMode ? .on : .off
            menuItem.toolTip = coordinator.strings.tooltip(.transcriptionMode)
            menu.addItem(menuItem)
        }
        menu.addItem(NSMenuItem.separator())
        let availableModels = coordinator.modelAvailabilityIndex.availableModels(for: coordinator.settings.pipelineMode)
        if availableModels.isEmpty {
            menu.addItem(disabledItem(
                coordinator.settings.pipelineMode == .systemASROnly
                    ? coordinator.strings.noLLMUsedForMode
                    : coordinator.strings.noObservedModels
            ))
        } else {
            for model in availableModels {
                let menuItem = item(
                    title: model.rawValue,
                    action: #selector(AppCoordinator.selectPipelineModel(_:)),
                    tooltip: coordinator.settings.pipelineMode == .inputAudio
                        ? coordinator.strings.tooltip(.inputAudioModel)
                        : coordinator.strings.tooltip(.textLLMModel)
                )
                menuItem.representedObject = model.rawValue
                menuItem.state = model == coordinator.currentPipelineModel ? .on : .off
                menu.addItem(menuItem)
            }
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(
            title: coordinator.strings.editModelList,
            action: #selector(AppCoordinator.openModelListConfigFile),
            tooltip: coordinator.strings.tooltip(.editModelList)
        ))
        return menu
    }

    func systemASRMenu() -> NSMenu {
        let menu = NSMenu(title: coordinator.strings.systemASR)
        menu.addItem(submenuItem(
            coordinator.strings.systemASREngineTitle(
                coordinator.effectiveSystemASREngine,
                externalProviderName: coordinator.selectedExternalASRPlugin?.displayName
            ),
            submenu: systemASREngineMenu(),
            tooltip: coordinator.strings.tooltip(.systemASREngine)
        ))
        let keywordHints = item(
            title: coordinator.strings.systemASRKeywordHints,
            action: #selector(AppCoordinator.toggleSystemASRKeywordHints),
            tooltip: coordinator.strings.tooltip(.systemASRKeywordHints)
        )
        keywordHints.state = coordinator.settings.systemASRKeywordHintsEnabled ? .on : .off
        menu.addItem(keywordHints)
        return menu
    }

    func systemASREngineMenu() -> NSMenu {
        let menu = NSMenu(title: coordinator.strings.systemASREngine)
        let entries = SystemASREngineMenuPlanner.entries(
            installedPlugins: coordinator.externalASRPlugins,
            selectedEngine: coordinator.effectiveSystemASREngine,
            selectedExternalProviderID: coordinator.settings.externalASRProviderID,
            speechAnalyzerAvailable: coordinator.speechAnalyzerAvailable,
            uiLanguage: coordinator.settings.uiLanguage
        )
        var didAddPluginSeparator = false
        for entry in entries {
            if case .externalASRProvider = entry.selection, !didAddPluginSeparator {
                menu.addItem(NSMenuItem.separator())
                didAddPluginSeparator = true
            }
            let menuItem = item(
                title: entry.title,
                action: action(for: entry.selection),
                tooltip: tooltip(for: entry.selection)
            )
            menuItem.representedObject = representedObject(for: entry.selection)
            menuItem.state = entry.isSelected ? .on : .off
            menuItem.isEnabled = entry.isEnabled
            menu.addItem(menuItem)
        }
        return menu
    }

    private func action(for selection: SystemASREngineMenuEntry.Selection) -> Selector {
        switch selection {
        case .builtIn:
            return #selector(AppCoordinator.selectSystemASREngine(_:))
        case .externalASRProvider:
            return #selector(AppCoordinator.selectExternalASRProvider(_:))
        }
    }

    private func representedObject(for selection: SystemASREngineMenuEntry.Selection) -> Any {
        switch selection {
        case .builtIn(let engine):
            return engine.rawValue
        case .externalASRProvider(let id):
            return ExternalASRProviderMenuSelection(providerID: id)
        }
    }

    private func tooltip(for selection: SystemASREngineMenuEntry.Selection) -> String {
        switch selection {
        case .builtIn(let engine):
            return coordinator.strings.systemASREngineTooltip(engine)
        case .externalASRProvider:
            return coordinator.strings.systemASREngineTooltip(.externalASR)
        }
    }
}
