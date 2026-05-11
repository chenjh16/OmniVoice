import AppKit
import Foundation

@MainActor
extension MenuBuilder {
    func languageMenu() -> NSMenu {
        let menu = NSMenu(title: coordinator.strings.uiLanguageTitle(coordinator.settings.uiLanguage))
        for language in UILanguage.allCases {
            let menuItem = item(title: language.displayName, action: #selector(AppCoordinator.selectLanguage(_:)))
            menuItem.representedObject = language.rawValue
            menuItem.state = language == coordinator.settings.uiLanguage ? .on : .off
            menu.addItem(menuItem)
        }
        return menu
    }

    func styleMenu() -> NSMenu {
        let selected = coordinator.currentStyleDescriptor.selection
        let menu = NSMenu(title: coordinator.strings.styleTitle(coordinator.currentStyleDescriptor))
        for style in TranscriptionStyle.menuOrder {
            let descriptor = TranscriptionStyleResolver.builtInDescriptor(style)
            let menuItem = item(
                title: coordinator.strings.styleMenuItem(descriptor),
                action: #selector(AppCoordinator.selectStyle(_:))
            )
            menuItem.representedObject = descriptor.selection.rawValue
            menuItem.state = descriptor.selection == selected ? .on : .off
            menuItem.toolTip = tooltip(for: descriptor)
            menu.addItem(menuItem)
        }
        if !coordinator.config.customStyles.isEmpty {
            menu.addItem(NSMenuItem.separator())
            for custom in coordinator.config.customStyles {
                let descriptor = TranscriptionStyleResolver.customDescriptor(custom)
                let menuItem = item(
                    title: coordinator.strings.styleMenuItem(descriptor),
                    action: #selector(AppCoordinator.selectStyle(_:))
                )
                menuItem.representedObject = descriptor.selection.rawValue
                menuItem.state = descriptor.selection == selected ? .on : .off
                menuItem.toolTip = tooltip(for: descriptor)
                menu.addItem(menuItem)
            }
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(
            title: coordinator.strings.editCustomStyles,
            action: #selector(AppCoordinator.openCustomStylesConfigFile),
            tooltip: coordinator.strings.tooltip(.customStyles)
        ))
        return menu
    }

    func keywordHintsMenu() -> NSMenu {
        let selectedIDs = Set(coordinator.settings.enabledKeywordGroupIDs)
        let menu = NSMenu(title: coordinator.strings.keywordHints)
        let enableItem = item(
            title: coordinator.strings.enableKeywordHints,
            action: #selector(AppCoordinator.toggleKeywordHints),
            tooltip: coordinator.strings.tooltip(.keywordHints)
        )
        enableItem.state = coordinator.settings.keywordHintsEnabled ? .on : .off
        menu.addItem(enableItem)
        menu.addItem(NSMenuItem.separator())

        if coordinator.config.keywordGroups.isEmpty {
            menu.addItem(disabledItem(coordinator.strings.noKeywordGroups))
        } else {
            for group in coordinator.config.keywordGroups {
                let menuItem = item(
                    title: coordinator.strings.keywordGroupMenuItem(group),
                    action: #selector(AppCoordinator.toggleKeywordGroup(_:)),
                    tooltip: group.localizedDescription(in: coordinator.settings.uiLanguage)
                        ?? coordinator.strings.tooltip(.keywordHints)
                )
                menuItem.representedObject = group.id
                menuItem.state = selectedIDs.contains(group.id) ? .on : .off
                menu.addItem(menuItem)
            }
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(item(
            title: coordinator.strings.editKeywords,
            action: #selector(AppCoordinator.openKeywordConfigFile),
            tooltip: coordinator.strings.tooltip(.keywordHints)
        ))
        return menu
    }

    func triggerMenu() -> NSMenu {
        let menu = NSMenu(title: coordinator.strings.triggerTitle(coordinator.settings.triggerKey))
        let captureView = TriggerCaptureMenuView(
            strings: coordinator.strings,
            selectedTriggerLabel: coordinator.strings.triggerLabel(coordinator.settings.triggerKey),
            onBegin: { [weak coordinator] view in
                coordinator?.beginTriggerCapture(view: view)
            }
        )
        coordinator.triggerCaptureRuntime.view = captureView
        let captureItem = NSMenuItem()
        captureItem.view = captureView
        menu.addItem(captureItem)
        menu.addItem(NSMenuItem.separator())
        addTriggerItem(TriggerKey.fnGlobe, to: menu)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(submenuItem(
            coordinator.settings.uiLanguage == .chinese ? "功能键" : "Function Keys",
            submenu: triggerSubmenu(TriggerKey.functionKeys)
        ))
        menu.addItem(submenuItem(
            coordinator.settings.uiLanguage == .chinese ? "修饰键" : "Modifiers",
            submenu: triggerSubmenu(TriggerKey.modifierKeys)
        ))
        menu.addItem(NSMenuItem.separator())
        addTriggerItem(TriggerKey.capsLock, to: menu)
        menu.addItem(NSMenuItem.separator())
        let continuousItem = item(
            title: coordinator.strings.continuousRecordingDoubleTap,
            action: #selector(AppCoordinator.toggleContinuousRecordingDoubleTap),
            tooltip: coordinator.continuousRecordingDoubleTapSupported
                ? coordinator.strings.tooltip(.continuousRecordingDoubleTap)
                : coordinator.strings.continuousRecordingUnsupportedForTrigger(coordinator.settings.triggerKey)
        )
        continuousItem.state = coordinator.settings.continuousRecordingDoubleTapEnabled ? .on : .off
        continuousItem.isEnabled = coordinator.continuousRecordingDoubleTapSupported
        menu.addItem(continuousItem)
        return menu
    }

    func triggerSubmenu(_ triggers: [TriggerKey]) -> NSMenu {
        let menu = NSMenu()
        for trigger in triggers {
            addTriggerItem(trigger, to: menu)
        }
        return menu
    }

    func addTriggerItem(_ trigger: TriggerKey, to menu: NSMenu) {
        let menuItem = item(
            title: coordinator.strings.triggerLabel(trigger),
            action: #selector(AppCoordinator.selectTrigger(_:))
        )
        menuItem.representedObject = trigger.identifier
        menuItem.state = trigger == coordinator.settings.triggerKey ? .on : .off
        menu.addItem(menuItem)
    }

    func durationMenu() -> NSMenu {
        let menu = NSMenu(title: coordinator.strings.recordingDurationTitle(
            min: coordinator.settings.minRecordingDuration,
            max: coordinator.settings.maxRecordingDuration
        ))
        menu.addItem(disabledItem(coordinator.strings.minRecordingDuration))
        for duration in MinRecordingDuration.allCases {
            let menuItem = item(title: duration.displayName, action: #selector(AppCoordinator.selectMinDuration(_:)))
            menuItem.representedObject = duration.rawValue
            menuItem.state = duration == coordinator.settings.minRecordingDuration ? .on : .off
            menu.addItem(menuItem)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(disabledItem(coordinator.strings.maxRecordingDuration))
        for duration in MaxRecordingDuration.allCases {
            let menuItem = item(title: duration.displayName, action: #selector(AppCoordinator.selectDuration(_:)))
            menuItem.representedObject = duration.rawValue
            menuItem.state = duration == coordinator.settings.maxRecordingDuration ? .on : .off
            menu.addItem(menuItem)
        }
        return menu
    }

    func hudStyleMenu() -> NSMenu {
        let menu = NSMenu(title: coordinator.strings.hudStyle)
        for style in HUDVisualStyleAvailability.availableStyles() {
            let menuItem = item(
                title: style.displayName(in: coordinator.settings.uiLanguage),
                action: #selector(AppCoordinator.selectHUDStyle(_:))
            )
            menuItem.representedObject = style.rawValue
            menuItem.state = style == coordinator.settings.hudVisualStyle ? .on : .off
            menu.addItem(menuItem)
        }
        return menu
    }

    func hudMessageDurationMenu() -> NSMenu {
        let menu = NSMenu(title: coordinator.strings.hudMessageDuration)
        for duration in HUDMessageDuration.allCases {
            let menuItem = item(
                title: duration.displayName,
                action: #selector(AppCoordinator.selectHUDMessageDuration(_:)),
                tooltip: coordinator.strings.tooltip(.hudMessageDuration)
            )
            menuItem.representedObject = duration.rawValue
            menuItem.state = duration == coordinator.settings.hudMessageDuration ? .on : .off
            menu.addItem(menuItem)
        }
        return menu
    }

    func hudRevealDelayMenu() -> NSMenu {
        let menu = NSMenu(title: coordinator.strings.hudRevealDelay)
        for delay in HUDRevealDelay.allCases {
            let menuItem = item(
                title: delay.displayName(in: coordinator.settings.uiLanguage),
                action: #selector(AppCoordinator.selectHUDRevealDelay(_:)),
                tooltip: coordinator.strings.tooltip(.hudRevealDelay)
            )
            menuItem.representedObject = delay.rawValue
            menuItem.state = delay == coordinator.settings.hudRevealDelay ? .on : .off
            menu.addItem(menuItem)
        }
        return menu
    }

    func displayHintsMenu() -> NSMenu {
        let menu = NSMenu(title: coordinator.strings.displayHints)
        let livePreview = item(
            title: coordinator.strings.liveASRPreviewTitle(enabled: coordinator.settings.liveASRPreviewEnabled),
            action: #selector(AppCoordinator.toggleLiveASRPreview),
            tooltip: coordinator.strings.tooltip(.liveASRPreview)
        )
        livePreview.state = coordinator.settings.liveASRPreviewEnabled ? .on : .off
        menu.addItem(livePreview)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(submenuItem(
            MenuTitleFormatter.hudStyle(coordinator.settings.hudVisualStyle, uiLanguage: coordinator.settings.uiLanguage),
            submenu: hudStyleMenu()
        ))
        menu.addItem(submenuItem(
            coordinator.strings.hudMessageDurationTitle(coordinator.settings.hudMessageDuration),
            submenu: hudMessageDurationMenu(),
            tooltip: coordinator.strings.tooltip(.hudMessageDuration)
        ))
        menu.addItem(submenuItem(
            coordinator.strings.hudRevealDelayTitle(coordinator.settings.hudRevealDelay),
            submenu: hudRevealDelayMenu(),
            tooltip: coordinator.strings.tooltip(.hudRevealDelay)
        ))
        return menu
    }

    func tooltip(for descriptor: TranscriptionStyleDescriptor) -> String {
        coordinator.strings.transcriptionStyleTooltip(descriptor)
    }

    func item(title: String, action: Selector?, tooltip: String? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = coordinator
        menuItem.toolTip = tooltip
        return menuItem
    }

    func disabledItem(_ title: String) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.isEnabled = false
        return menuItem
    }

    func submenuItem(_ title: String, submenu: NSMenu, tooltip: String? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.submenu = submenu
        menuItem.toolTip = tooltip
        return menuItem
    }
}
