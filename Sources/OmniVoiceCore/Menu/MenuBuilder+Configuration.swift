import AppKit
import Foundation

@MainActor
extension MenuBuilder {
    func configurationMenu() -> NSMenu {
        let menu = NSMenu(title: coordinator.strings.configuration)
        menu.addItem(submenuItem(
            coordinator.strings.apiSourceTitle(coordinator.config, mode: coordinator.settings.pipelineMode),
            submenu: apiSourceMenu()
        ))
        menu.addItem(submenuItem(
            coordinator.strings.modelConfigurationTitle(
                mode: coordinator.settings.pipelineMode,
                model: coordinator.currentPipelineModel
            ),
            submenu: modelConfigurationMenu()
        ))
        menu.addItem(submenuItem(coordinator.strings.systemASR, submenu: systemASRMenu()))
        menu.addItem(submenuItem(
            coordinator.strings.latencyIntervalTitle(coordinator.config.latencySettings.interval),
            submenu: latencyIntervalMenu()
        ))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(
            title: coordinator.strings.openConfigFile,
            action: #selector(AppCoordinator.openConfigFile),
            tooltip: coordinator.strings.tooltip(.openConfigFile)
        ))
        menu.addItem(item(
            title: coordinator.strings.reloadConfig,
            action: #selector(AppCoordinator.reloadConfig),
            tooltip: coordinator.strings.tooltip(.reloadConfig)
        ))
        menu.addItem(item(
            title: coordinator.strings.refreshModels,
            action: #selector(AppCoordinator.refreshModelsAction),
            tooltip: coordinator.strings.tooltip(.refreshModels)
        ))
        menu.addItem(item(
            title: coordinator.connectionCheckTitle,
            action: #selector(AppCoordinator.checkConnectionAndLatency),
            tooltip: coordinator.strings.tooltip(.connectionCheck)
        ))
        return menu
    }

    func apiSourceMenu() -> NSMenu {
        let menu = NSMenu(title: coordinator.strings.apiSource)
        let supportingSourceIDs = coordinator.modelAvailabilityIndex.sourceIDsSupporting(
            coordinator.currentPipelineModel,
            mode: coordinator.settings.pipelineMode
        )
        let hasModelMeasurements = coordinator.modelAvailabilityIndex.hasMeasurements
        let systemASROnly = coordinator.settings.pipelineMode == .systemASROnly
        let autoItem = item(
            title: coordinator.strings.autoAPISourceMenuItem(resolvedSourceID: coordinator.config.resolvedSourceID),
            action: #selector(AppCoordinator.selectAPISource(_:)),
            tooltip: systemASROnly ? coordinator.strings.tooltip(.systemASROnlyMode) : coordinator.strings.tooltip(.apiSourceAuto)
        )
        autoItem.representedObject = MimoConfig.autoSourceID
        autoItem.state = coordinator.config.activeSourceID == MimoConfig.autoSourceID ? .on : .off
        autoItem.isEnabled = !systemASROnly && (!hasModelMeasurements || !supportingSourceIDs.isEmpty)
        menu.addItem(autoItem)
        menu.addItem(NSMenuItem.separator())
        for source in coordinator.config.sourceSummaries {
            let supportsCurrentModel = !systemASROnly && (!hasModelMeasurements || supportingSourceIDs.contains(source.id))
            let menuItem = item(
                title: coordinator.strings.apiSourceMenuItem(
                    source,
                    latency: coordinator.sourceLatencyRuntime.results[source.id]
                ),
                action: #selector(AppCoordinator.selectAPISource(_:)),
                tooltip: systemASROnly
                    ? coordinator.strings.tooltip(.systemASROnlyMode)
                    : (
                        supportsCurrentModel
                            ? coordinator.strings.tooltip(.apiSourceAvailable)
                            : coordinator.strings.apiSourceDoesNotExposeCurrentModel(coordinator.currentPipelineModel)
                    )
            )
            menuItem.representedObject = source.id
            menuItem.state = source.id == coordinator.config.activeSourceID ? .on : .off
            menuItem.isEnabled = supportsCurrentModel
            menu.addItem(menuItem)
        }
        if coordinator.config.sourceSummaries.isEmpty {
            menu.addItem(disabledItem(coordinator.strings.configWarning(ConfigWarning.raw(.fileMissing))))
        }
        menu.addItem(NSMenuItem.separator())
        let systemOnlyItem = item(
            title: coordinator.strings.useSystemASROnly,
            action: #selector(AppCoordinator.toggleSystemASROnlyMode),
            tooltip: coordinator.strings.tooltip(.systemASROnlyMode)
        )
        systemOnlyItem.state = systemASROnly ? .on : .off
        menu.addItem(systemOnlyItem)
        return menu
    }

    func latencyIntervalMenu() -> NSMenu {
        let menu = NSMenu(title: coordinator.strings.latencyInterval)
        for interval in ConfigLatencyInterval.allCases {
            let menuItem = item(
                title: coordinator.strings.latencyIntervalLabel(interval),
                action: #selector(AppCoordinator.selectLatencyInterval(_:)),
                tooltip: coordinator.strings.tooltip(.latency)
            )
            menuItem.representedObject = interval.rawValue
            menuItem.state = interval == coordinator.config.latencySettings.interval ? .on : .off
            menu.addItem(menuItem)
        }
        return menu
    }
}
