import Foundation

struct ChatCompletionRequest: Encodable {
    let model: String
    let stream = true
    let temperature = 0
    let thinking: Thinking?
    let modalities: [String]?
    let messages: [Message]

    init(model: String, instruction: String, base64WAV: String, profile: ModelRequestProfile) {
        self.model = model
        self.thinking = profile.sendsMimoThinkingDisabled ? Thinking(type: "disabled") : nil
        self.modalities = profile.sendsTextModalities ? ["text"] : nil
        self.messages = [
            Message(content: [
                .text(instruction),
                .inputAudio(data: base64WAV, format: "wav")
            ])
        ]
    }

    struct Thinking: Encodable {
        let type: String
    }

    struct Message: Encodable {
        let role = "user"
        let content: [ContentBlock]
    }

    enum ContentBlock: Encodable {
        case text(String)
        case inputAudio(data: String, format: String)

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case inputAudio = "input_audio"
        }

        enum AudioCodingKeys: String, CodingKey {
            case data
            case format
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .inputAudio(let data, let format):
                try container.encode("input_audio", forKey: .type)
                var audio = container.nestedContainer(keyedBy: AudioCodingKeys.self, forKey: .inputAudio)
                try audio.encode(data, forKey: .data)
                try audio.encode(format, forKey: .format)
            }
        }
    }
}

struct TextChatCompletionRequest: Encodable {
    let model: String
    let stream = true
    let temperature = 0
    let thinking: Thinking?
    let messages: [Message]

    init(model: String, instruction: String, profile: ModelRequestProfile) {
        self.model = model
        self.thinking = profile.sendsMimoThinkingDisabled ? Thinking(type: "disabled") : nil
        self.messages = [
            Message(role: "system", content: "You are a careful speech dictation post-processor. Output only the final text."),
            Message(role: "user", content: instruction)
        ]
    }

    struct Thinking: Encodable {
        let type: String
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }
}
