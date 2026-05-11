import Foundation

extension AppCoordinator {
    func updateLastDiagnosticInsertion(_ reason: String?) {
        let diagnostic = RuntimeDiagnostic(
            stage: "injection_complete",
            host: "local",
            insertionFallbackReason: reason,
            errorKind: reason,
            details: ["result": reason == nil ? "inserted" : "fallback"]
        )
        RuntimeDiagnostic.log(diagnostic)
        recordDiagnostic(diagnostic)
    }

    func recordDiagnostic(_ diagnostic: RuntimeDiagnostic) {
        lastDiagnostic = diagnostic
        rebuildMenu()
    }

    func recordLocalDiagnostic(
        stage: String,
        errorKind: String? = nil,
        details: [String: String] = [:]
    ) {
        let diagnostic = RuntimeDiagnostic(
            stage: stage,
            host: "local",
            errorKind: errorKind,
            details: details
        )
        RuntimeDiagnostic.log(diagnostic)
        recordDiagnostic(diagnostic)
        automationEventSink?.record(AutomationEvent(
            stage: stage,
            errorKind: errorKind,
            details: details
        ))
    }

    func recordHUDDiagnostic(stage: String) {
        recordSurfaceDiagnostic(
            stage: stage,
            snapshot: hud.diagnosticSnapshot,
            screenshotPNGData: hud.renderedPNGData()
        )
    }

    func recordActionPanelDiagnostic(stage: String) {
        recordSurfaceDiagnostic(
            stage: stage,
            snapshot: actionPanel.diagnosticSnapshot,
            screenshotPNGData: actionPanel.renderedPNGData()
        )
    }

    func recordSurfaceDiagnostic(
        stage: String,
        snapshot: SurfaceDiagnosticSnapshot,
        screenshotPNGData: Data?
    ) {
        guard let frame = snapshot.frame else {
            recordLocalDiagnostic(
                stage: stage,
                errorKind: "\(snapshot.panelType)_not_visible",
                details: [
                    "panel_type": snapshot.panelType,
                    "level": snapshot.levelName,
                    "is_visible": snapshot.isVisible ? "true" : "false"
                ]
            )
            automationEventSink?.record(AutomationEvent(
                stage: stage,
                errorKind: "\(snapshot.panelType)_not_visible",
                details: [
                    "panel_type": snapshot.panelType,
                    "level": snapshot.levelName,
                    "is_visible": snapshot.isVisible ? "true" : "false"
                ],
                surface: snapshot,
                screenshotPNGData: nil
            ))
            return
        }
        var details = [
            "panel_type": snapshot.panelType,
            "level": snapshot.levelName,
            "is_visible": snapshot.isVisible ? "true" : "false",
            "x": String(format: "%.1f", frame.origin.x),
            "y": String(format: "%.1f", frame.origin.y),
            "width": String(format: "%.1f", frame.width),
            "height": String(format: "%.1f", frame.height)
        ]
        if let windowNumber = snapshot.windowNumber {
            details["window_number"] = "\(windowNumber)"
        }
        recordLocalDiagnostic(stage: stage, details: details)
        automationEventSink?.record(AutomationEvent(
            stage: stage,
            details: details,
            surface: snapshot,
            screenshotPNGData: screenshotPNGData
        ))
    }
}
