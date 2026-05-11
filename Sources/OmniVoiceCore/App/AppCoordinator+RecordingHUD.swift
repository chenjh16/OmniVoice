import AppKit
import Foundation

extension AppCoordinator {
    func scheduleListeningHUDReveal() {
        cancelListeningHUDRevealTimer()
        listeningHUDShownForCurrentRecording = false
        recordingTimingRuntime.listeningHUDRevealTimer.schedule(
            interval: settings.hudRevealDelay.seconds,
            repeats: false
        ) { [weak self] in
            self?.revealListeningHUDIfNeeded()
        }
    }

    func revealListeningHUDIfNeeded() {
        recordingTimingRuntime.listeningHUDRevealTimer.cancel()
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
        recordingTimingRuntime.listeningHUDRevealTimer.cancel()
    }

    func resetListeningHUDRevealState() {
        cancelListeningHUDRevealTimer()
        listeningHUDShownForCurrentRecording = false
    }
}
