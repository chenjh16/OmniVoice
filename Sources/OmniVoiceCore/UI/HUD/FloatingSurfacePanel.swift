import AppKit

enum FloatingSurfacePanelRole {
    case hud
    case actionPanel
}

enum FloatingSurfacePanelConfigurator {
    static func configure(_ panel: NSPanel, role: FloatingSurfacePanelRole) {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = role == .hud

        switch role {
        case .hud:
            panel.hasShadow = HUDSurfaceMetrics.usesSystemShadow
        case .actionPanel:
            panel.hasShadow = ActionPanelSurfaceMetrics.usesSystemShadow
        }
    }
}
