import AppKit
import Foundation

extension AppCoordinator {
    func scheduleListeningHUDReveal() {
        cancelListeningHUDRevealTimer()
        listeningHUDShownForCurrentRecording = false
        listeningHUDRevealTimer = Timer.scheduledTimer(
            withTimeInterval: settings.hudRevealDelay.seconds,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.revealListeningHUDIfNeeded()
            }
        }
    }

    func revealListeningHUDIfNeeded() {
        listeningHUDRevealTimer?.invalidate()
        listeningHUDRevealTimer = nil
        guard ListeningHUDRevealPlanner.shouldReveal(
            isRecording: state == .recording,
            cancelled: false
        ) else {
            return
        }
        listeningHUDShownForCurrentRecording = true
        hud.showListening(text: strings.listening)
        let liveASRPreviewText = liveASRCoordinator.previewText
        if settings.liveASRPreviewEnabled, !liveASRPreviewText.isEmpty {
            hud.updateListeningPreview(liveASRPreviewText, badge: liveASRPreviewBadge)
        }
        recordHUDDiagnostic(stage: "hud_show_listening")
    }

    func cancelListeningHUDRevealTimer() {
        listeningHUDRevealTimer?.invalidate()
        listeningHUDRevealTimer = nil
    }

    func resetListeningHUDRevealState() {
        cancelListeningHUDRevealTimer()
        listeningHUDShownForCurrentRecording = false
    }
}
