import Foundation

struct PendingTranscription: Sendable {
    let result: AudioRecordingResult
    let mode: TranscriptionPipelineMode
    let model: AllowedSpeechModel
    let instruction: String
    let styleSelection: TranscriptionStyleSelection
    let shouldAutoInsert: Bool
    let autoInsertSkipReason: String?
    let originalFocus: FocusSnapshot?
    let fallbackResult: PreviousPanelResult?
    let liveASRFinalTask: Task<ASRRecognitionResult, Error>?
}

struct RecordingStopContext: Sendable {
    let elapsed: TimeInterval?
    let mode: TranscriptionPipelineMode
    let validationPolicy: RecordingValidationPolicy
    let listeningHUDWasShown: Bool
    let model: AllowedSpeechModel
    let instruction: String
    let styleSelection: TranscriptionStyleSelection
    let shouldAutoInsert: Bool
    let autoInsertSkipReason: String?
    let originalFocus: FocusSnapshot?
}

struct PreviousPanelResult: Sendable {
    let text: String
    let instruction: String
    let styleSelection: TranscriptionStyleSelection
}

@MainActor
final class RecordingPipelineCoordinator {
    private(set) var stopInProgress = false

    func beginStopTask(
        source: any RecordingSource,
        minimumDurationSeconds: Double,
        context: RecordingStopContext,
        onSuccess: @escaping @MainActor (AudioRecordingResult, RecordingStopContext) -> Void,
        onFailure: @escaping @MainActor (Error, RecordingStopContext) -> Void
    ) -> Task<Void, Never> {
        stopInProgress = true
        let validationPolicy = context.validationPolicy
        return Task { @MainActor in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try source.stop(
                        minimumDurationSeconds: minimumDurationSeconds,
                        validationPolicy: validationPolicy
                    )
                }.value
                guard !Task.isCancelled else { return }
                onSuccess(result, context)
            } catch {
                guard !Task.isCancelled else { return }
                onFailure(error, context)
            }
        }
    }

    func completeStop(
        result: AudioRecordingResult,
        context: RecordingStopContext,
        liveASRFinalTask: Task<ASRRecognitionResult, Error>?
    ) -> PendingTranscription? {
        guard stopInProgress else { return nil }
        stopInProgress = false
        return PendingTranscription(
            result: result,
            mode: context.mode,
            model: context.model,
            instruction: context.instruction,
            styleSelection: context.styleSelection,
            shouldAutoInsert: context.shouldAutoInsert,
            autoInsertSkipReason: context.autoInsertSkipReason,
            originalFocus: context.originalFocus,
            fallbackResult: nil,
            liveASRFinalTask: liveASRFinalTask
        )
    }

    func failStop() -> Bool {
        guard stopInProgress else { return false }
        stopInProgress = false
        return true
    }

    func cancelPendingStop() -> Bool {
        failStop()
    }

    func clearStopState() {
        stopInProgress = false
    }
}
