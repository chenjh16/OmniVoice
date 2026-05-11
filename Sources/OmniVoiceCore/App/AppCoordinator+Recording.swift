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

    func startLiveASRIfNeeded() {
        liveASRCoordinator.prepareForStart()
        guard shouldRunLiveASRForCurrentRecording else { return }
        let configuredEngine = effectiveSystemASREngine
        let primaryEngine = effectiveLiveASREngine
        if primaryEngine != configuredEngine {
            recordLocalDiagnostic(
                stage: "live_asr_recovery_engine_override",
                details: [
                    "configured_engine": configuredEngine.rawValue,
                    "live_engine": primaryEngine.rawValue,
                    "cooldown_until": iso8601String(speechAnalyzerRecoveryCooldownUntil)
                ]
            )
        }
        let engines = LiveASREngineFallbackPlanner.engines(primary: primaryEngine)
        let keywordHints = currentSystemASRKeywordHintsContext
        let task = Task { [weak self] in
            guard let self else { return }
            for (index, engine) in engines.enumerated() {
                let options = SystemSpeechRecognitionOptions(
                    language: .defaultLanguage,
                    engine: engine,
                    keywordHints: keywordHints
                )
                do {
                    let session = try await systemSpeechRecognizer.makeLiveSession(
                        options: options,
                        onUpdate: { [weak self] update in
                            DispatchQueue.main.async {
                                self?.handleLiveASRUpdate(update)
                            }
                        }
                    )
                    if Task.isCancelled {
                        session.cancel()
                        return
                    }
                    installLiveASRSession(session, engine: options.engine)
                    return
                } catch {
                    let fallbackEngine = engines.indices.contains(index + 1) ? engines[index + 1] : nil
                    recordLiveASRStartFailure(
                        error,
                        engine: engine,
                        primaryEngine: primaryEngine,
                        fallbackEngine: fallbackEngine
                    )
                    if fallbackEngine != nil, !Task.isCancelled {
                        continue
                    }
                    liveASRCoordinator.handleStartFailure(errorKind: diagnosticKind(for: error))
                    return
                }
            }
        }
        liveASRCoordinator.beginPreparation(task)
    }

    func recordLiveASRStartFailure(
        _ error: Error,
        engine: SystemASREngine,
        primaryEngine: SystemASREngine,
        fallbackEngine: SystemASREngine?
    ) {
        var details = [
            "engine": engine.rawValue,
            "primary_engine": primaryEngine.rawValue,
            "preview_enabled": settings.liveASRPreviewEnabled ? "true" : "false",
            "pipeline_mode": settings.pipelineMode.rawValue
        ]
        if let fallbackEngine {
            details["fallback_engine"] = fallbackEngine.rawValue
        }
        if engine == .speechAnalyzer {
            markSpeechAnalyzerLiveStartFailedForRecovery()
        }
        recordLocalDiagnostic(
            stage: "live_asr_start_failed",
            errorKind: diagnosticKind(for: error),
            details: details
        )
    }

    func installLiveASRSession(
        _ session: any LiveSystemSpeechRecognitionSession,
        engine: SystemASREngine
    ) {
        let result = liveASRCoordinator.install(session, isRecording: state == .recording)
        guard case let .installed(bufferOverflowed) = result else { return }
        recordLocalDiagnostic(
            stage: "live_asr_started",
            details: [
                "engine": engine.rawValue,
                "preview_enabled": settings.liveASRPreviewEnabled ? "true" : "false",
                "pipeline_mode": settings.pipelineMode.rawValue,
                "buffer_overflowed": bufferOverflowed ? "true" : "false"
            ]
        )
    }

    func handleLiveASRChunk(_ chunk: AudioSampleChunk) {
        switch liveASRCoordinator.append(
            chunk,
            shouldRun: state == .recording && shouldRunLiveASRForCurrentRecording
        ) {
        case let .bufferOverflowed(limitSeconds):
            recordLocalDiagnostic(
                stage: "live_asr_buffer_overflowed",
                details: [
                    "pipeline_mode": settings.pipelineMode.rawValue,
                    "limit_seconds": String(format: "%.1f", limitSeconds)
                ]
            )
        case .ignored, .appendedToSession, .buffered:
            break
        }
    }

    func handleLiveASRUpdate(_ update: LiveASRUpdate) {
        guard let text = liveASRCoordinator.acceptPreview(
            update,
            isRecording: state == .recording,
            previewEnabled: settings.liveASRPreviewEnabled
        ) else { return }
        if listeningHUDShownForCurrentRecording {
            hud.updateListeningPreview(text, badge: liveASRPreviewBadge)
        }
    }

    var liveASRPreviewBadge: String? {
        settings.pipelineMode == .systemASROnly ? strings.liveASRRecognitionBadge : strings.liveASRPreviewBadge
    }

    func makeLiveASRFinalTaskForStoppedRecording(
        useForSystemPipeline: Bool
    ) -> Task<ASRRecognitionResult, Error>? {
        liveASRCoordinator.makeFinalTask(useForSystemPipeline: useForSystemPipeline)
    }

    func cancelLiveASRSession() {
        liveASRCoordinator.cancel()
    }

    @discardableResult
    func cancelPendingRecordingStop() -> Bool {
        guard recordingPipeline.cancelPendingStop() else { return false }
        cancelLiveASRSession()
        return true
    }

    func handleRecordingTriggerDown() {
        let action = continuousRecordingStateMachine.triggerDown(
            doubleTapEnabled: shouldUseContinuousRecordingDoubleTap,
            appIsRecording: state == .recording
        )

        switch action {
        case .beginRecording:
            beginRecording()
        case .ignoreStopPending:
            recordLocalDiagnostic(
                stage: "continuous_recording_stop_tap_ignored",
                details: ["trigger": settings.triggerKey.identifier]
            )
        case .beginStopTap:
            beginContinuousRecordingStopTap()
        case .enterContinuousRecording:
            continuousRecordingTapTimeout?.cancel()
            continuousRecordingTapTimeout = nil
            recordLocalDiagnostic(
                stage: "continuous_recording_started",
                details: [
                    "trigger": settings.triggerKey.identifier,
                    "double_tap_interval_seconds": String(format: "%.3f", continuousRecordingDoubleTapInterval)
                ]
            )
        }
    }

    func handleRecordingTriggerUp() {
        let tapDuration = recordingStartDate.map { Date().timeIntervalSince($0) }
        let action = continuousRecordingStateMachine.triggerUp(
            doubleTapEnabled: shouldUseContinuousRecordingDoubleTap,
            appIsRecording: state == .recording,
            tapDuration: tapDuration
        )

        switch action {
        case .finishRecording:
            finishRecordingAndTranscribe()
        case let .finishStopTap(clearTriggerState):
            finishContinuousRecordingStopTap(clearTriggerState: clearTriggerState)
        case .scheduleSecondTapWindow:
            scheduleContinuousRecordingSecondTapWindow(firstTapDuration: tapDuration ?? 0)
        case .ignoreTriggerUp:
            recordLocalDiagnostic(
                stage: "continuous_recording_trigger_up_ignored",
                details: ["trigger": settings.triggerKey.identifier]
            )
        }
    }

    func beginContinuousRecordingStopTap() {
        scheduleContinuousRecordingStopFallback()
        recordLocalDiagnostic(
            stage: "continuous_recording_stop_tap",
            details: ["trigger": settings.triggerKey.identifier]
        )
    }

    func scheduleContinuousRecordingStopFallback() {
        continuousRecordingStopFallback?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.expireContinuousRecordingStopTap()
            }
        }
        continuousRecordingStopFallback = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + ContinuousRecordingStopPlanner.releaseFallbackInterval,
            execute: workItem
        )
    }

    func finishContinuousRecordingStopTap(clearTriggerState: Bool) {
        continuousRecordingStopFallback?.cancel()
        continuousRecordingStopFallback = nil
        if clearTriggerState {
            eventTap.clearCurrentTriggerStateForContinuousRecording()
        }
        recordLocalDiagnostic(
            stage: clearTriggerState ? "continuous_recording_stop_release_fallback" : "continuous_recording_stop_release",
            details: ["trigger": settings.triggerKey.identifier]
        )
        finishRecordingAndTranscribe()
    }

    func expireContinuousRecordingStopTap() {
        switch continuousRecordingStateMachine.stopReleaseFallback() {
        case let .finishStopTap(clearTriggerState):
            finishContinuousRecordingStopTap(clearTriggerState: clearTriggerState)
        case .finishRecording:
            finishRecordingAndTranscribe()
        case .ignore:
            break
        }
    }

    func scheduleContinuousRecordingSecondTapWindow(firstTapDuration: TimeInterval) {
        continuousRecordingTapTimeout?.cancel()
        let interval = continuousRecordingDoubleTapInterval
        recordLocalDiagnostic(
            stage: "continuous_recording_first_tap_pending",
            details: [
                "trigger": settings.triggerKey.identifier,
                "first_tap_seconds": String(format: "%.3f", firstTapDuration),
                "double_tap_interval_seconds": String(format: "%.3f", interval)
            ]
        )
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.expireContinuousRecordingSecondTapWindow()
            }
        }
        continuousRecordingTapTimeout = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
    }

    func expireContinuousRecordingSecondTapWindow() {
        continuousRecordingTapTimeout = nil
        switch continuousRecordingStateMachine.secondTapTimeout() {
        case .finishRecording:
            recordLocalDiagnostic(
                stage: "continuous_recording_second_tap_timeout",
                details: ["trigger": settings.triggerKey.identifier]
            )
            finishRecordingAndTranscribe()
        case let .finishStopTap(clearTriggerState):
            finishContinuousRecordingStopTap(clearTriggerState: clearTriggerState)
        case .ignore:
            break
        }
    }

    func resetContinuousRecordingTriggerState(preserveIgnoredUp: Bool = false) {
        continuousRecordingTapTimeout?.cancel()
        continuousRecordingTapTimeout = nil
        continuousRecordingStopFallback?.cancel()
        continuousRecordingStopFallback = nil
        continuousRecordingStateMachine.reset(preserveIgnoredUp: preserveIgnoredUp)
    }

    func beginRecording() {
        let isAutomation = automationContinuation != nil
        guard isAutomation || (settings.listeningEnabled && !globalStopActive && state == .idle) else {
            recordLocalDiagnostic(
                stage: "recording_start_ignored",
                errorKind: "state_not_ready",
                details: [
                    "state": String(describing: state),
                    "listening_enabled": settings.listeningEnabled ? "true" : "false",
                    "stopped": globalStopActive ? "true" : "false"
                ]
            )
            completeAutomation(
                ok: false,
                pending: nil,
                injectionResult: nil,
                fallbackReason: nil,
                errorKind: "recording_start_ignored"
            )
            return
        }
        guard state == .idle else {
            completeAutomation(
                ok: false,
                pending: nil,
                injectionResult: nil,
                fallbackReason: nil,
                errorKind: "state_not_idle"
            )
            return
        }
        recordingFocus = textInjector.captureFocusSnapshot(
            targetBundleIdentifier: automationOptions?.targetBundleIdentifier
        )
        recordingStartDate = Date()
        state = .recording
        eventTap.setCancellationActive(true)
        updateEventTapTriggerSuppression()
        actionPanel.cancel()
        rebuildMenu()
        recordLocalDiagnostic(
            stage: "recording_start_requested",
            details: [
                "trigger": settings.triggerKey.identifier,
                "min_duration_seconds": String(format: "%.3f", settings.minRecordingDuration.seconds),
                "max_duration_seconds": "\(settings.maxRecordingDuration.rawValue)"
            ]
        )
        do {
            startLiveASRIfNeeded()
            try recordingSource.start()
            recordLocalDiagnostic(stage: "recording_started", details: ["trigger": settings.triggerKey.identifier])
            scheduleListeningHUDReveal()
            maxRecordingTimer?.invalidate()
            maxRecordingTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.maxRecordingDuration.rawValue), repeats: false) { [weak self] _ in
                Task { @MainActor in self?.finishRecordingAndTranscribe() }
            }
            rebuildMenu()
        } catch {
            state = .idle
            resetContinuousRecordingTriggerState()
            cancelLiveASRSession()
            recordingStartDate = nil
            recordingFocus = nil
            resetListeningHUDRevealState()
            eventTap.setCancellationActive(false)
            updateEventTapTriggerSuppression()
            recordLocalDiagnostic(
                stage: "recording_start_failed",
                errorKind: diagnosticKind(for: error)
            )
            hud.showWarningStatus(sanitizedMessage(for: error), duration: warningDuration)
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
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil

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
