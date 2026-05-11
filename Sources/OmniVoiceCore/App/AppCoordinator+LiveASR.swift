import AppKit
import Foundation

extension AppCoordinator {
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
}
