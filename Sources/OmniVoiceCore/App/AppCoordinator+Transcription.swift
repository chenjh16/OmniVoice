import AppKit
import Foundation

extension AppCoordinator {
    func startTranscription(_ pending: PendingTranscription) {
        resetListeningHUDRevealState()
        recordingPipeline.clearStopState()
        state = .transcribing
        eventTap.setCancellationActive(true)
        updateEventTapTriggerSuppression()
        let showsModelProgress = TranscriptionHUDPresentationPolicy.showsModelProgress(for: pending.mode)
        hud.showTranscribing(
            recordingSeconds: pending.result.durationSeconds,
            text: showsModelProgress ? strings.transcribing : strings.finishingRecognition,
            showsProgress: showsModelProgress
        )
        recordHUDDiagnostic(stage: "hud_show_transcribing")
        rebuildMenu()
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let finalText: String
                switch pending.mode {
                case .inputAudio:
                    finalText = try await client.transcribe(
                        wavData: pending.result.wavData,
                        model: pending.model,
                        instruction: pending.instruction,
                        recordingSeconds: pending.result.durationSeconds,
                        overallRMS: pending.result.overallRMS,
                        allowEmptyFinalText: false,
                        onDelta: { [weak self] delta in
                            DispatchQueue.main.async {
                                self?.hud.appendTranscriptionDelta(delta)
                            }
                        }
                    )
                case .systemASRTextLLM:
                    finalText = try await self.transcribeWithSystemASRAndTextLLM(pending)
                case .systemASROnly:
                    finalText = try await self.transcribeWithSystemASROnly(pending)
                }
                if Task.isCancelled { return }
                await self.finishTranscription(
                    finalText: finalText,
                    pending: pending
                )
            } catch TranscriptionFlowControl.asrDraftShown {
                return
            } catch {
                await self.failTranscription(error, pending: pending)
            }
        }
    }

    func transcribeWithSystemASRAndTextLLM(_ pending: PendingTranscription) async throws -> String {
        let asrResult = try await recognizeSystemASRDraft(for: pending)
        recordLocalDiagnostic(
            stage: "system_asr_complete",
            details: [
                "draft_chars": "\(asrResult.text.count)",
                "low_confidence_segments": "\(asrResult.lowConfidenceSegments.count)",
                "alternatives": "\(asrResult.alternatives.count)",
                "apple_online_allowed": asrResult.allowedAppleServerRecognition ? "true" : "false"
            ]
        )
        let descriptor = TranscriptionStyleResolver.resolve(
            selection: pending.styleSelection,
            customStyles: config.customStyles
        )
        let prompt = ASRTextPromptBuilder.prompt(
            asrResult: asrResult,
            styleDescriptor: descriptor,
            keywordHints: currentSystemASRKeywordHintsContext
        )
        do {
            return try await client.completeText(
                model: pending.model,
                instruction: prompt,
                allowEmptyFinalText: false,
                onDelta: { [weak self] delta in
                    DispatchQueue.main.async {
                        self?.hud.appendTranscriptionDelta(delta)
                    }
                }
            )
        } catch {
            await showASRDraftAfterTextLLMFailure(asrResult: asrResult, error: error, pending: pending)
            throw TranscriptionFlowControl.asrDraftShown
        }
    }

    func transcribeWithSystemASROnly(_ pending: PendingTranscription) async throws -> String {
        let asrResult = try await recognizeSystemASRDraft(for: pending)
        recordLocalDiagnostic(
            stage: "system_asr_only_complete",
            details: [
                "draft_chars": "\(asrResult.text.count)",
                "low_confidence_segments": "\(asrResult.lowConfidenceSegments.count)",
                "alternatives": "\(asrResult.alternatives.count)",
                "apple_online_allowed": asrResult.allowedAppleServerRecognition ? "true" : "false"
            ]
        )
        return asrResult.text
    }

    func recognizeSystemASRDraft(for pending: PendingTranscription) async throws -> ASRRecognitionResult {
        if let liveASRFinalTask = pending.liveASRFinalTask {
            do {
                let result = try await liveASRFinalTask.value
                recordLocalDiagnostic(
                    stage: "live_system_asr_complete",
                    details: [
                        "draft_chars": "\(result.text.count)",
                        "apple_online_allowed": result.allowedAppleServerRecognition ? "true" : "false"
                    ]
                )
                return result
            } catch {
                recordLocalDiagnostic(
                    stage: "live_system_asr_failed",
                    errorKind: diagnosticKind(for: error)
                )
            }
        }
        let result = try await systemSpeechRecognizer.recognize(
            wavData: pending.result.wavData,
            options: SystemSpeechRecognitionOptions(
                language: .defaultLanguage,
                engine: effectiveSystemASREngine,
                keywordHints: currentSystemASRKeywordHintsContext
            )
        )
        recordLocalDiagnostic(
            stage: "file_system_asr_complete",
            details: [
                "draft_chars": "\(result.text.count)",
                "low_confidence_segments": "\(result.lowConfidenceSegments.count)",
                "alternatives": "\(result.alternatives.count)",
                "apple_online_allowed": result.allowedAppleServerRecognition ? "true" : "false"
            ]
        )
        return result
    }

    func showASRDraftAfterTextLLMFailure(
        asrResult: ASRRecognitionResult,
        error: Error,
        pending: PendingTranscription
    ) async {
        await MainActor.run {
            state = .idle
            eventTap.setCancellationActive(false)
            updateEventTapTriggerSuppression()
            transcriptionTask = nil
            let draftPending = PendingTranscription(
                result: pending.result,
                mode: pending.mode,
                model: pending.model,
                instruction: pending.instruction,
                styleSelection: pending.styleSelection,
                shouldAutoInsert: false,
                autoInsertSkipReason: "text_llm_failed",
                originalFocus: pending.originalFocus,
                fallbackResult: nil,
                liveASRFinalTask: nil
            )
            pendingTranscription = draftPending
            recordLocalDiagnostic(
                stage: "text_llm_failed_after_system_asr",
                errorKind: diagnosticKind(for: error),
                details: [
                    "model": pending.model.rawValue,
                    "source": config.resolvedSourceID,
                    "http_status": diagnosticHTTPStatus(for: error) ?? "none",
                    "asr_draft_chars": "\(asrResult.text.count)",
                    "low_confidence_segments": "\(asrResult.lowConfidenceSegments.count)",
                    "alternatives": "\(asrResult.alternatives.count)",
                    "unsupported_text_model": TextLLMFailureClassifier.isLikelyUnsupportedTextModel(error) ? "true" : "false"
                ]
            )
            showResultActionPanel(
                text: asrResult.text,
                title: TextLLMFailureClassifier.isLikelyUnsupportedTextModel(error)
                    ? strings.textLLMUnsupportedTitle
                    : strings.textLLMFailedTitle,
                pending: draftPending
            )
            completeAutomation(
                ok: false,
                pending: draftPending,
                injectionResult: "action_panel",
                fallbackReason: "text_llm_failed",
                errorKind: diagnosticKind(for: error)
            )
            rebuildMenu()
        }
    }

    func finishTranscription(
        finalText: String,
        pending: PendingTranscription
    ) async {
        state = .idle
        eventTap.setCancellationActive(false)
        updateEventTapTriggerSuppression()
        transcriptionTask = nil

        guard !finalText.isEmpty else {
            hud.showWarningStatus(strings.noTextRecognized, duration: warningDuration)
            rebuildMenu()
            applyPendingConfigHotReloadIfNeeded()
            completeAutomation(
                ok: false,
                pending: pending,
                injectionResult: nil,
                fallbackReason: nil,
                errorKind: "empty_final_text"
            )
            return
        }

        if pending.shouldAutoInsert {
            let result = await textInjector.insertFinalText(
                finalText,
                originalFocus: pending.originalFocus,
                targetBundleIdentifier: automationOptions?.targetBundleIdentifier
            )
            switch result {
            case .inserted:
                updateLastDiagnosticInsertion(nil)
                pendingTranscription = nil
                recordingFocus = nil
                hud.completeAndHide()
                completeAutomation(
                    ok: true,
                    pending: pending,
                    injectionResult: "inserted",
                    fallbackReason: nil,
                    errorKind: nil,
                    finalText: finalText
                )
            case .fallback(let reason):
                updateLastDiagnosticInsertion(reason.rawValue)
                showResultActionPanel(text: finalText, pending: pending)
                completeAutomation(
                    ok: false,
                    pending: pending,
                    injectionResult: "fallback",
                    fallbackReason: reason.rawValue,
                    errorKind: reason.rawValue,
                    finalText: finalText
                )
            }
        } else {
            if let autoInsertSkipReason = pending.autoInsertSkipReason {
                recordLocalDiagnostic(
                    stage: "injection_skipped",
                    errorKind: autoInsertSkipReason,
                    details: ["text_chars": "\(finalText.count)"]
                )
            }
            showResultActionPanel(text: finalText, pending: pending)
            if automationOptions?.forceActionPanel == true {
                try? await Task.sleep(nanoseconds: 550_000_000)
                recordActionPanelDiagnostic(stage: "action_panel_stable_result")
            }
            completeAutomation(
                ok: automationOptions?.forceActionPanel == true,
                pending: pending,
                injectionResult: automationOptions?.forceActionPanel == true ? "action_panel" : "fallback",
                fallbackReason: pending.autoInsertSkipReason ?? "auto_insert_disabled",
                errorKind: pending.autoInsertSkipReason ?? "auto_insert_disabled",
                finalText: finalText
            )
        }
        rebuildMenu()
        applyPendingConfigHotReloadIfNeeded()
    }

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

    func failTranscription(_ error: Error, pending: PendingTranscription?) async {
        state = .idle
        eventTap.setCancellationActive(false)
        updateEventTapTriggerSuppression()
        transcriptionTask = nil
        if Task.isCancelled {
            hud.showTransientStatus(strings.cancelled, duration: warningDuration)
            pendingTranscription = nil
            recordingFocus = nil
            completeAutomation(
                ok: false,
                pending: pending,
                injectionResult: nil,
                fallbackReason: nil,
                errorKind: "cancelled"
            )
        } else {
            showRetryActionPanel(error: error, pending: pending)
            completeAutomation(
                ok: false,
                pending: pending,
                injectionResult: nil,
                fallbackReason: nil,
                errorKind: diagnosticKind(for: error)
            )
        }
        rebuildMenu()
        applyPendingConfigHotReloadIfNeeded()
    }
}
