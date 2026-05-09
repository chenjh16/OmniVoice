import AppKit
import Foundation

extension AppCoordinator {
    func runRecordingReplayForAutomation(
        options: RecordingReplayAutomationOptions
    ) async -> RecordingReplayAutomationResult {
        guard automationContinuation == nil else {
            return RecordingReplayAutomationResult(
                ok: false,
                recordingSeconds: nil,
                wavBytes: nil,
                overallRMS: nil,
                originalBundleIdentifier: recordingFocus?.bundleIdentifier,
                originalAppName: recordingFocus?.appName,
                originalFocusFailure: recordingFocus?.failureReason.rawValue,
                injectionResult: nil,
                fallbackReason: nil,
                errorKind: "automation_already_running",
                qualitySummary: nil
            )
        }

        return await withCheckedContinuation { continuation in
            automationOptions = options
            automationRecordingResult = nil
            automationContinuation = continuation
            if let uiLanguage = options.uiLanguage {
                automationPreviousUILanguage = settings.uiLanguage
                settings.uiLanguage = uiLanguage
            }
            let visualStyle = options.hudVisualStyle ?? settings.hudVisualStyle
            hud.setVisualStyle(visualStyle)
            actionPanel.setVisualStyle(visualStyle)
            beginRecording()
            startAutomationGUIFrameCaptureIfNeeded()

            guard automationContinuation != nil else { return }
            let replaySource = recordingSource as? any ReplayRecordingSource
            Task { @MainActor [weak self] in
                if let replaySource {
                    await replaySource.waitUntilReplayFinished()
                } else {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
                guard let self, self.automationContinuation != nil else { return }
                self.finishRecordingAndTranscribe()
            }
        }
    }

    func completeAutomation(
        ok: Bool,
        pending: PendingTranscription?,
        injectionResult: String?,
        fallbackReason: String?,
        errorKind: String?,
        finalText: String? = nil
    ) {
        guard let continuation = automationContinuation else { return }
        stopAutomationGUIFrameCapture()
        let recording = pending?.result ?? automationRecordingResult
        let focus = pending?.originalFocus ?? recordingFocus
        let qualitySummary = finalText.flatMap {
            TranscriptQualitySummary.evaluate(
                finalText: $0,
                expectedKeywords: automationOptions?.expectedKeywords ?? []
            )
        }
        if let previous = automationPreviousUILanguage {
            settings.uiLanguage = previous
        }
        automationContinuation = nil
        automationOptions = nil
        automationRecordingResult = nil
        automationPreviousUILanguage = nil
        continuation.resume(returning: RecordingReplayAutomationResult(
            ok: ok,
            recordingSeconds: recording?.durationSeconds,
            wavBytes: recording?.wavData.count,
            overallRMS: recording?.overallRMS,
            originalBundleIdentifier: focus?.bundleIdentifier,
            originalAppName: focus?.appName,
            originalFocusFailure: focus?.failureReason.rawValue,
            injectionResult: injectionResult,
            fallbackReason: fallbackReason,
            errorKind: errorKind,
            qualitySummary: qualitySummary
        ))
    }

    func startAutomationGUIFrameCaptureIfNeeded() {
        guard let options = automationOptions,
              options.recordGUIFrames,
              automationGUIFrameTimer == nil else { return }
        automationGUIFrameIndex = 0
        recordAutomationGUIFrame(stage: "gui_frame_start")
        let interval = max(1.0 / 30.0, min(options.guiFrameIntervalSeconds, 1.0))
        automationGUIFrameTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordAutomationGUIFrame(stage: "gui_frame")
            }
        }
    }

    func stopAutomationGUIFrameCapture() {
        guard automationGUIFrameTimer != nil || automationGUIFrameIndex > 0 else { return }
        recordAutomationGUIFrame(stage: "gui_frame_final")
        automationGUIFrameTimer?.invalidate()
        automationGUIFrameTimer = nil
    }

    func recordAutomationGUIFrame(stage: String) {
        guard automationOptions?.recordGUIFrames == true else { return }
        let actionPanelSnapshot = actionPanel.diagnosticSnapshot
        let hudSnapshot = hud.diagnosticSnapshot
        let snapshot: SurfaceDiagnosticSnapshot
        let screenshotPNGData: Data?
        if actionPanelSnapshot.isVisible {
            snapshot = actionPanelSnapshot
            screenshotPNGData = actionPanel.renderedPNGData()
        } else if hudSnapshot.isVisible {
            snapshot = hudSnapshot
            screenshotPNGData = hud.renderedPNGData()
        } else {
            return
        }
        guard screenshotPNGData != nil else { return }
        automationGUIFrameIndex += 1
        var details = [
            "frame_index": "\(automationGUIFrameIndex)",
            "panel_type": snapshot.panelType,
            "level": snapshot.levelName,
            "is_visible": snapshot.isVisible ? "true" : "false"
        ]
        if let frame = snapshot.frame {
            details["x"] = String(format: "%.1f", frame.origin.x)
            details["y"] = String(format: "%.1f", frame.origin.y)
            details["width"] = String(format: "%.1f", frame.width)
            details["height"] = String(format: "%.1f", frame.height)
        }
        if let windowNumber = snapshot.windowNumber {
            details["window_number"] = "\(windowNumber)"
        }
        automationEventSink?.record(AutomationEvent(
            stage: stage,
            details: details,
            surface: snapshot,
            screenshotPNGData: screenshotPNGData
        ))
    }
}
