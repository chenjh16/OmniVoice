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
            coordinator.strings.systemASREngineTitle(coordinator.effectiveSystemASREngine),
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
        for engine in SystemASREngine.allCases {
            let menuItem = item(
                title: engine.displayName(in: coordinator.settings.uiLanguage),
                action: #selector(AppCoordinator.selectSystemASREngine(_:)),
                tooltip: coordinator.strings.systemASREngineTooltip(engine)
            )
            menuItem.representedObject = engine.rawValue
            menuItem.state = engine == coordinator.effectiveSystemASREngine ? .on : .off
            if engine == .speechAnalyzer && !coordinator.speechAnalyzerAvailable {
                menuItem.isEnabled = false
            }
            menu.addItem(menuItem)
        }
        return menu
    }
}
