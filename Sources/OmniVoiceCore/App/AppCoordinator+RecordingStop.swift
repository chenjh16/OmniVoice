import AppKit
import Foundation

extension AppCoordinator {
    func finishRecordingAndTranscribe() {
        guard state == .recording else {
            recordLocalDiagnostic(
                stage: "recording_stop_ignored",
                errorKind: "state_not_recording",
                details: ["state": String(describing: state)]
            )
            return
        }
        resetContinuousRecordingTriggerState(preserveIgnoredUp: true)
        let elapsed = recordingStartDate.map { Date().timeIntervalSince($0) }
        let mode = settings.pipelineMode
        let validationPolicy = RecordingValidationPolicyResolver.policy(for: mode)
        recordLocalDiagnostic(
            stage: "recording_stop_requested",
            details: {
                var details = elapsed.map { ["elapsed_seconds": String(format: "%.3f", $0)] } ?? [:]
                details["pipeline_mode"] = mode.rawValue
                details["validation_policy"] = validationPolicy.rawValue
                return details
            }()
        )
        let listeningHUDWasShown = listeningHUDShownForCurrentRecording
        cancelListeningHUDRevealTimer()
        recordingTimingRuntime.maxRecordingTimer.cancel()

        let model = automationOptions?.model ?? currentPipelineModel
        let styleDescriptor = automationOptions?.styleSelection.map {
            TranscriptionStyleResolver.resolve(selection: $0, customStyles: config.customStyles)
        } ?? currentStyleDescriptor
        let instruction = TranscriptionInstructionBuilder.instruction(
            descriptor: styleDescriptor,
            keywordHints: currentKeywordHintsContext
        )
        let shouldAutoInsert: Bool
        let autoInsertSkipReason: String?
        if automationOptions?.forceActionPanel == true {
            shouldAutoInsert = false
            autoInsertSkipReason = "forced_action_panel"
        } else if automationOptions?.forceAutoInsert == true {
            shouldAutoInsert = true
            autoInsertSkipReason = nil
        } else {
            autoInsertSkipReason = settings.autoInsert && globalStopActive ? "global_stop_auto_insert_disabled" : nil
            shouldAutoInsert = settings.autoInsert && !globalStopActive
        }
        let context = RecordingStopContext(
            elapsed: elapsed,
            mode: mode,
            validationPolicy: validationPolicy,
            listeningHUDWasShown: listeningHUDWasShown,
            model: model,
            instruction: instruction,
            styleSelection: styleDescriptor.selection,
            shouldAutoInsert: shouldAutoInsert,
            autoInsertSkipReason: autoInsertSkipReason,
            originalFocus: recordingFocus
        )

        state = .transcribing
        eventTap.setCancellationActive(true)
        updateEventTapTriggerSuppression()
        let recordingSecondsForHUD = max(elapsed ?? 0, settings.minRecordingDuration.seconds)
        let showsModelProgress = TranscriptionHUDPresentationPolicy.showsModelProgress(for: mode)
        hud.showTranscribing(
            recordingSeconds: recordingSecondsForHUD,
            text: showsModelProgress ? strings.transcribing : strings.finishingRecognition,
            showsProgress: showsModelProgress
        )
        recordHUDDiagnostic(stage: "hud_show_transcribing")
        rebuildMenu()

        transcriptionTask = recordingPipeline.beginStopTask(
            source: recordingSource,
            minimumDurationSeconds: settings.minRecordingDuration.seconds,
            context: context,
            onSuccess: { [weak self] result, context in
                self?.finishRecordingStop(result: result, context: context)
            },
            onFailure: { [weak self] error, context in
                self?.failRecordingStop(error, context: context)
            }
        )
    }

    func finishRecordingStop(
        result: AudioRecordingResult,
        context: RecordingStopContext
    ) {
        guard state == .transcribing, recordingPipeline.stopInProgress else { return }
        transcriptionTask = nil
        automationRecordingResult = result
        recordingStartDate = nil
        listeningHUDShownForCurrentRecording = false
        recordLocalDiagnostic(
            stage: "recording_stopped",
            details: [
                "recording_seconds": String(format: "%.3f", result.durationSeconds),
                "rms": String(format: "%.5f", result.overallRMS),
                "wav_bytes": "\(result.wavData.count)",
                "pipeline_mode": context.mode.rawValue,
                "validation_policy": context.validationPolicy.rawValue
            ]
        )

        let asrGateState = liveASRCoordinator.gateState
        let asrGateDecision = DirectAudioASRGatePlanner.decision(
            mode: context.mode,
            gateState: asrGateState,
            overallRMS: result.overallRMS
        )
        if case let .block(errorKind) = asrGateDecision {
            blockDirectAudioForASRGate(
                result: result,
                context: context,
                gateState: asrGateState,
                errorKind: errorKind
            )
            return
        }
        if asrGateDecision.reason == "asr_gate_bypassed_strong_rms" {
            recordLocalDiagnostic(
                stage: "direct_audio_asr_gate_bypassed",
                details: directAudioASRGateDiagnosticDetails(
                    result: result,
                    context: context,
                    gateState: asrGateState,
                    decision: asrGateDecision.reason
                )
            )
        }

        let liveASRFinalTask = makeLiveASRFinalTaskForStoppedRecording(
            useForSystemPipeline: context.mode.usesSystemASR
        )
        guard let pending = recordingPipeline.completeStop(
            result: result,
            context: context,
            liveASRFinalTask: liveASRFinalTask
        ) else { return }
        pendingTranscription = pending
        startTranscription(pending)
    }

    func blockDirectAudioForASRGate(
        result: AudioRecordingResult,
        context: RecordingStopContext,
        gateState: LiveASRCoordinator.GateState,
        errorKind: String
    ) {
        _ = recordingPipeline.failStop()
        cancelLiveASRSession()
        state = .idle
        eventTap.setCancellationActive(false)
        updateEventTapTriggerSuppression()
        pendingTranscription = nil
        recordingFocus = nil
        automationRecordingResult = nil
        recordLocalDiagnostic(
            stage: "direct_audio_asr_gate_blocked",
            errorKind: errorKind,
            details: directAudioASRGateDiagnosticDetails(
                result: result,
                context: context,
                gateState: gateState,
                decision: errorKind
            )
        )
        hud.showWarningStatus(strings.noReliableSpeechRecognized, duration: warningDuration)
        rebuildMenu()
        completeAutomation(
            ok: false,
            pending: nil,
            injectionResult: nil,
            fallbackReason: errorKind,
            errorKind: errorKind
        )
        applyPendingConfigHotReloadIfNeeded()
    }

    func directAudioASRGateDiagnosticDetails(
        result: AudioRecordingResult,
        context: RecordingStopContext,
        gateState: LiveASRCoordinator.GateState,
        decision: String
    ) -> [String: String] {
        var details = [
            "recording_seconds": String(format: "%.3f", result.durationSeconds),
            "rms": String(format: "%.5f", result.overallRMS),
            "pipeline_mode": context.mode.rawValue,
            "asr_gate_state": gateState.diagnosticValue,
            "asr_gate_decision": decision,
            "live_engine": effectiveLiveASREngine.rawValue,
            "asr_text_chars": "\(gateState.textCharacterCount)"
        ]
        if case let .startFailed(errorKind) = gateState {
            details["asr_gate_error"] = errorKind
        }
        return details
    }

    func failRecordingStop(
        _ error: Error,
        context: RecordingStopContext
    ) {
        guard recordingPipeline.failStop() else { return }
        transcriptionTask = nil
        state = .idle
        cancelLiveASRSession()
        recordingStartDate = nil
        listeningHUDShownForCurrentRecording = false
        eventTap.setCancellationActive(false)
        updateEventTapTriggerSuppression()
        let message = sanitizedMessage(for: error)
        let validationStatus = recordingValidationStatus(for: error)
        let shouldShowHUD = RecordingStopFailurePresentationPlanner.shouldShowHUD(
            validationStatus: validationStatus,
            listeningHUDWasShown: context.listeningHUDWasShown
        )
        recordLocalDiagnostic(
            stage: "recording_stop_failed",
            errorKind: diagnosticKind(for: error),
            details: {
                var details = context.elapsed.map { ["elapsed_seconds": String(format: "%.3f", $0)] } ?? [:]
                details["hud_visible_before_stop"] = context.listeningHUDWasShown ? "true" : "false"
                details["shown_to_user"] = shouldShowHUD ? "true" : "false"
                details["pipeline_mode"] = context.mode.rawValue
                details["validation_policy"] = context.validationPolicy.rawValue
                return details
            }()
        )
        if shouldShowHUD {
            hud.showWarningStatus(message, duration: warningDuration)
        } else {
            hud.hide()
        }
        rebuildMenu()
        completeAutomation(
            ok: false,
            pending: nil,
            injectionResult: nil,
            fallbackReason: nil,
            errorKind: diagnosticKind(for: error)
        )
    }
}
