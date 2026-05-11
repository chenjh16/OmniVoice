import Foundation

enum DirectAudioASRGateDecision: Equatable, Sendable {
    case allow(reason: String)
    case block(errorKind: String)

    var reason: String {
        switch self {
        case .allow(let reason):
            return reason
        case .block(let errorKind):
            return errorKind
        }
    }
}

enum DirectAudioASRGatePlanner {
    static let strongSpeechRMS: Float = 0.018
    static let noReliableSpeechErrorKind = "asr_gate_no_text"

    static func decision(
        mode: TranscriptionPipelineMode,
        gateState: LiveASRCoordinator.GateState,
        overallRMS: Float
    ) -> DirectAudioASRGateDecision {
        guard mode == .inputAudio else {
            return .allow(reason: "not_input_audio")
        }

        switch gateState {
        case .sawText:
            return .allow(reason: "asr_gate_saw_text")
        case .running:
            if overallRMS >= strongSpeechRMS {
                return .allow(reason: "asr_gate_bypassed_strong_rms")
            }
            return .block(errorKind: noReliableSpeechErrorKind)
        case .notStarted, .startFailed, .bufferOverflowed:
            return .allow(reason: "asr_gate_unavailable")
        }
    }
}
