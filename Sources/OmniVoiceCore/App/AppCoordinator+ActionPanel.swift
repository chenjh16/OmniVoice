import AppKit
import Foundation

extension AppCoordinator {
    func showRetryActionPanel(error: Error, pending: PendingTranscription?) {
        let message = sanitizedMessage(for: error)
        let startFrame = hud.frameForMorphAndHide()
        actionPanel.showRetry(
            title: strings.requestFailed,
            message: message,
            retryTitle: strings.retry,
            cancelTitle: strings.cancel,
            from: startFrame,
            onRetry: { [weak self] in
                guard let self else { return }
                if let pending {
                    self.startTranscription(pending)
                }
            },
            onCancel: { [weak self] in
                guard let self else { return }
                if let pending, let fallback = pending.fallbackResult {
                    let restored = PendingTranscription(
                        result: pending.result,
                        mode: pending.mode,
                        model: pending.model,
                        instruction: fallback.instruction,
                        styleSelection: fallback.styleSelection,
                        shouldAutoInsert: false,
                        autoInsertSkipReason: nil,
                        originalFocus: pending.originalFocus,
                        fallbackResult: nil,
                        liveASRFinalTask: nil
                    )
                    self.pendingTranscription = restored
                    self.showResultActionPanel(text: fallback.text, pending: restored)
                } else {
                    self.pendingTranscription = nil
                    self.recordingFocus = nil
                }
            }
        )
        recordActionPanelDiagnostic(stage: "action_panel_show_retry")
    }

    func showResultActionPanel(text: String, title: String = "", pending: PendingTranscription) {
        let startFrame = hud.frameForMorphAndHide()
        let descriptor = TranscriptionStyleResolver.resolve(
            selection: pending.styleSelection,
            customStyles: config.customStyles
        )
        actionPanel.showResult(
            title: title,
            text: text,
            copyTitle: strings.copy,
            styleTitle: strings.panelStyleSwitchTitle(descriptor),
            styleOptions: actionPanelStyleOptions(),
            selectedStyle: descriptor.selection,
            cancelTitle: strings.cancel,
            copiedTitle: strings.copied,
            from: startFrame,
            onCopy: { [weak self] in
                self?.pendingTranscription = nil
                self?.recordingFocus = nil
            },
            onStyleSelected: { [weak self] selection in
                guard let self else { return }
                self.switchResultStyle(selection, previousText: text, previousPending: pending)
            },
            onCancel: { [weak self] in
                self?.pendingTranscription = nil
                self?.recordingFocus = nil
            }
        )
        recordActionPanelDiagnostic(stage: "action_panel_show_result")
    }

    func actionPanelStyleOptions() -> [ActionPanelStyleOption] {
        TranscriptionStyleResolver.menuDescriptors(customStyles: config.customStyles).map { descriptor in
            ActionPanelStyleOption(
                selection: descriptor.selection,
                title: strings.styleMenuItem(descriptor),
                tooltip: tooltip(for: descriptor)
            )
        }
    }

    func switchResultStyle(
        _ selection: TranscriptionStyleSelection,
        previousText: String,
        previousPending: PendingTranscription
    ) {
        let descriptor = TranscriptionStyleResolver.resolve(
            selection: selection,
            customStyles: config.customStyles
        )
        let instruction = TranscriptionInstructionBuilder.instruction(
            descriptor: descriptor,
            keywordHints: currentKeywordHintsContext
        )
        let pending = PendingTranscription(
            result: previousPending.result,
            mode: previousPending.mode,
            model: previousPending.model,
            instruction: instruction,
            styleSelection: descriptor.selection,
            shouldAutoInsert: false,
            autoInsertSkipReason: "panel_style_switch",
            originalFocus: previousPending.originalFocus,
            fallbackResult: PreviousPanelResult(
                text: previousText,
                instruction: previousPending.instruction,
                styleSelection: previousPending.styleSelection
            ),
            liveASRFinalTask: nil
        )
        pendingTranscription = pending
        recordLocalDiagnostic(
            stage: "panel_style_switch",
            details: ["style": descriptor.selection.rawValue]
        )
        startTranscription(pending)
    }
}
