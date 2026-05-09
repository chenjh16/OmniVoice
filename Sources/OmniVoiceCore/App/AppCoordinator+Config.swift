import AppKit
import Foundation

extension AppCoordinator {
    @objc func toggleLaunchAtLogin() {
        let enable = LaunchAtLoginController.status() != .enabled
        do {
            try LaunchAtLoginController.setEnabled(enable)
            lastLaunchAtLoginError = nil
        } catch {
            lastLaunchAtLoginError = sanitizedMessage(for: error)
            hud.showWarningStatus(lastLaunchAtLoginError ?? strings.operationFailed, duration: warningDuration)
        }
        _ = persistCurrentPreferences()
        rebuildMenu()
    }

    @objc func reloadConfig() {
        let loaded = loadConfig()
        applyLoadedConfigPreferences(loaded, syncLaunchAtLogin: true)
        client = makeClient(config: config)
        lastTestConnectionResult = nil
        configHotReload.clearMessage()
        scheduleLatencyChecks()
        hud.showTransientStatus(strings.configReloaded, duration: warningDuration)
        rebuildMenu()
    }

    func handleConfigFileChanged() {
        switch configHotReload.handleFileChanged(isIdle: state == .idle) {
        case .ignore, .markPending:
            return
        case .applyNow:
            applyConfigHotReload()
        }
    }

    func markInternalConfigWrite() {
        configHotReload.markInternalWrite()
    }

    func applyPendingConfigHotReloadIfNeeded() {
        guard configHotReload.consumePendingIfIdle(isIdle: state == .idle) else { return }
        applyConfigHotReload()
    }

    func applyConfigHotReload() {
        switch configStore.loadValidConfigWithoutRepair() {
        case .valid(let loaded):
            configHotReload.markValidApplied()
            applyLoadedConfigPreferences(loaded, syncLaunchAtLogin: true)
            client = makeClient(config: config)
            lastTestConnectionResult = nil
            scheduleLatencyChecks()
            recordLocalDiagnostic(
                stage: "config_hot_reload_applied",
                details: [
                    "keyword_groups": "\(loaded.keywordGroups.count)",
                    "enabled_keyword_groups": "\(loaded.preferences.enabledKeywordGroupIDs.count)"
                ]
            )
            hud.showTransientStatus(strings.configHotReloaded, duration: warningDuration)
            rebuildMenu()
        case .invalid(let issues):
            let data = try? Data(contentsOf: configStore.configFileURL)
            let fingerprint = ConfigHotReloadController.fingerprint(data: data)
            guard configHotReload.shouldReportInvalidConfig(fingerprint: fingerprint) else { return }
            let message: String
            if let exportURL = configStore.exportCurrentConfigSnapshot(uiLanguage: settings.uiLanguage) {
                message = strings.configHotReloadInvalidExported(exportURL.path)
                recordLocalDiagnostic(
                    stage: "config_hot_reload_invalid",
                    errorKind: "invalid_config",
                    details: [
                        "issues": issues.joined(separator: ","),
                        "export_path": exportURL.path
                    ]
                )
            } else {
                message = strings.configWarning("Config warning: config.jsonc could not be read")
                recordLocalDiagnostic(
                    stage: "config_hot_reload_invalid",
                    errorKind: "invalid_config_export_failed",
                    details: ["issues": issues.joined(separator: ",")]
                )
            }
            configHotReload.setInvalidMessage(message)
            hud.showWarningStatus(message, duration: warningDuration)
            rebuildMenu()
        }
    }

    @objc func selectAPISource(_ sender: NSMenuItem) {
        guard settings.pipelineMode.requiresModelAPI else { return }
        guard let sourceID = sender.representedObject as? String else { return }
        markInternalConfigWrite()
        _ = configStore.saveActiveSource(sourceID, uiLanguage: settings.uiLanguage)
        client = makeClient(config: config)
        lastTestConnectionResult = nil
        scheduleLatencyChecks()
        rebuildMenu()
    }

    @objc func selectLatencyInterval(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? Int else { return }
        let interval = ConfigLatencyInterval.safeSelection(rawValue)
        markInternalConfigWrite()
        _ = configStore.saveLatencyInterval(interval, uiLanguage: settings.uiLanguage)
        scheduleLatencyChecks()
        rebuildMenu()
    }

    @objc func openConfigFile() {
        openConfigFileAtSection(.root)
    }

    @objc func openModelListConfigFile() {
        openConfigFileAtSection(.modelsAudioLLM)
    }

    @objc func openKeywordConfigFile() {
        openConfigFileAtSection(.keywordGroups)
    }

    @objc func openCustomStylesConfigFile() {
        openConfigFileAtSection(.customStyles)
    }

    func openConfigFileAtSection(_ section: ConfigFileSection) {
        _ = configStore.ensureValidConfig(uiLanguage: settings.uiLanguage)
        guard configStore.fileManager.fileExists(atPath: configStore.configFileURL.path) else {
            hud.showWarningStatus(strings.configFileOpenFailed, duration: warningDuration)
            return
        }
        let configText = (try? String(contentsOf: configStore.configFileURL, encoding: .utf8)) ?? ""
        let line = ConfigFileLineLocator.lineNumber(in: configText, section: section)
        let plan = ConfigFileOpenPlanner.plan(fileURL: configStore.configFileURL, line: line, column: 1)
        openConfigFileUsingPlan(configStore.configFileURL, plan: plan)
    }

    func openConfigFileUsingPlan(_ fileURL: URL, plan: ConfigFileOpenPlan) {
        switch plan.method {
        case let .applicationBundle(appURL, displayName):
            let configuration = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: configuration) { [weak self] _, error in
                guard let self else { return }
                DispatchQueue.main.async {
                    if error == nil {
                        self.hud.showTransientStatus(self.strings.configFileOpenedInEditor(displayName), duration: self.warningDuration)
                    } else {
                        self.openConfigFileWithDefaultApp(fileURL, noEditorFound: true)
                    }
                }
            }
        case let .command(commandURL, displayName):
            do {
                let process = Process()
                process.executableURL = commandURL
                process.arguments = plan.arguments.isEmpty ? [fileURL.path] : plan.arguments
                try process.run()
                hud.showTransientStatus(strings.configFileOpenedInEditor(displayName), duration: warningDuration)
            } catch {
                openConfigFileWithDefaultApp(fileURL, noEditorFound: true)
            }
        case .systemDefault:
            openConfigFileWithDefaultApp(fileURL, noEditorFound: true)
        }
    }

    func openConfigFileWithDefaultApp(_ fileURL: URL, noEditorFound: Bool) {
        if NSWorkspace.shared.open(fileURL) {
            let message = noEditorFound ? strings.configFileOpenedWithDefaultApp : strings.configFileOpened
            hud.showTransientStatus(message, duration: warningDuration)
        } else {
            hud.showWarningStatus(strings.configFileOpenFailed, duration: warningDuration)
        }
    }

    @objc func refreshModelsAction() {
        Task { await refreshModels(showStatus: true) }
    }

    func scheduleLatencyChecks() {
        latencyTimer?.invalidate()
        latencyTimer = nil
        guard config.latencySettings.interval != .off else { return }
        Task { await refreshSourceLatencies(showStatus: false) }
        guard let seconds = config.latencySettings.interval.seconds else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshSourceLatencies(showStatus: false)
            }
        }
        latencyTimer = timer
    }

    func refreshSourceLatencies(showStatus: Bool) async {
        guard !config.sources.isEmpty else {
            if showStatus {
                hud.showWarningStatus(strings.configWarning("Config file missing"), duration: warningDuration)
            }
            return
        }
        let sourceJobs = config.sources.compactMap { source -> (source: MimoConfigSource, config: MimoConfig)? in
            guard let sourceConfig = config.selectingSource(source.id) else { return nil }
            return (source, sourceConfig)
        }
        let sourceOrder = Dictionary(uniqueKeysWithValues: sourceJobs.enumerated().map { ($0.element.source.id, $0.offset) })
        let orderedResults = await withTaskGroup(
            of: (source: MimoConfigSource, measurement: SourceLatencyMeasurement).self,
            returning: [(source: MimoConfigSource, measurement: SourceLatencyMeasurement)].self
        ) { group in
            for job in sourceJobs {
                group.addTask {
                    let measurement = await MimoAPIClient(config: job.config).measureModelsLatency()
                    return (job.source, measurement)
                }
            }
            var results: [(source: MimoConfigSource, measurement: SourceLatencyMeasurement)] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { lhs, rhs in
                (sourceOrder[lhs.source.id] ?? Int.max) < (sourceOrder[rhs.source.id] ?? Int.max)
            }
        }
        let measurements = Dictionary(uniqueKeysWithValues: orderedResults.map { ($0.source.id, $0.measurement) })
        for result in orderedResults {
            let source = result.source
            let measurement = result.measurement
            recordLocalDiagnostic(
                stage: "source_latency_measured",
                errorKind: measurement.errorKind,
                details: [
                    "source_id": source.id,
                    "host": source.baseURL.host ?? source.baseURL.absoluteString,
                    "http_status": measurement.httpStatus.map(String.init) ?? "none",
                    "milliseconds": measurement.milliseconds.map(String.init) ?? "none",
                    "reachable": measurement.reachable ? "true" : "false",
                    "speech_models": measurement.allowedSpeechModels(in: config.modelCatalogs.inputAudioModels).map(\.rawValue).joined(separator: ",")
                ]
            )
        }
        sourceLatencyResults = SourceLatencyRefreshPlanner.mergedMeasurements(
            existing: sourceLatencyResults,
            refreshed: measurements,
            configuredSourceIDs: config.sources.map(\.id)
        )
        let resolved = config.resolvingSource(using: sourceLatencyResults)
        client = makeClient(config: resolved)
        if showStatus {
            hud.showTransientStatus(strings.connectionLatencyCompleted, duration: warningDuration)
        }
        rebuildMenu()
        applyPendingConfigHotReloadIfNeeded()
    }

    @objc func checkConnectionAndLatency() {
        isTestingConnection = true
        rebuildMenu()
        Task {
            await refreshSourceLatencies(showStatus: false)
            client = makeClient(config: config.resolvingSource(using: sourceLatencyResults))
            let result = await client.testConnection(selectedModel: currentPipelineModel, runAudioProbe: false)
            lastTestConnectionResult = result
            isTestingConnection = false
            let message = strings.connectionCheckMessage(result)
            if result.modelsReachable, result.selectedModelAllowed {
                hud.showTransientStatus(message, duration: warningDuration)
            } else {
                hud.showWarningStatus(message, duration: warningDuration)
            }
            rebuildMenu()
        }
    }
}
