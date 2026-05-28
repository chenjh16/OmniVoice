import Foundation

enum ExternalASRResponse: Equatable, Sendable {
    case ready
    case partial(text: String, replace: Bool)
    case final(text: String)
    case error(message: String)
}

enum ExternalASRProtocol {
    static let sampleRate = 16_000
    static let channels = 1

    static func startRequest(streaming: Bool) throws -> Data {
        try encode(RequestEnvelope(
            type: "start",
            sampleRate: sampleRate,
            channels: channels,
            streaming: streaming,
            pcm16: nil
        ))
    }

    static func audioRequest(pcm16: Data) throws -> Data {
        try encode(RequestEnvelope(
            type: "audio",
            sampleRate: nil,
            channels: nil,
            streaming: nil,
            pcm16: pcm16.base64EncodedString()
        ))
    }

    static func finishRequest() throws -> Data {
        try encode(RequestEnvelope(
            type: "finish",
            sampleRate: nil,
            channels: nil,
            streaming: nil,
            pcm16: nil
        ))
    }

    static func response(fromLine line: String) throws -> ExternalASRResponse {
        guard let data = line.data(using: .utf8) else {
            throw SystemSpeechRecognitionError.recognitionFailed("External ASR returned invalid UTF-8")
        }
        let envelope = try JSONDecoder().decode(ResponseEnvelope.self, from: data)
        switch envelope.type {
        case "ready":
            return .ready
        case "partial":
            return .partial(text: envelope.text ?? "", replace: envelope.replace ?? false)
        case "final":
            return .final(text: envelope.text ?? "")
        case "error":
            return .error(message: envelope.message ?? "External ASR helper failed")
        default:
            throw SystemSpeechRecognitionError.recognitionFailed("External ASR returned unknown response: \(envelope.type)")
        }
    }

    private static func encode(_ envelope: RequestEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(envelope)
    }
}

private struct RequestEnvelope: Encodable {
    let type: String
    let sampleRate: Int?
    let channels: Int?
    let streaming: Bool?
    let pcm16: String?

    enum CodingKeys: String, CodingKey {
        case type
        case sampleRate = "sample_rate"
        case channels
        case streaming
        case pcm16
    }
}

private struct ResponseEnvelope: Decodable {
    let type: String
    let text: String?
    let message: String?
    let replace: Bool?
}
