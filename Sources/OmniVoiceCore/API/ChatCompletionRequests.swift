import Foundation

struct ChatCompletionThinking: Encodable {
    let type: String
}

struct ChatCompletionMessage<Content: Encodable>: Encodable {
    let role: String
    let content: Content

    init(role: String = "user", content: Content) {
        self.role = role
        self.content = content
    }
}

struct ChatCompletionRequest: Encodable {
    let model: String
    let stream = true
    let temperature = 0
    let thinking: ChatCompletionThinking?
    let modalities: [String]?
    let messages: [ChatCompletionMessage<[ContentBlock]>]

    init(model: String, instruction: String, base64WAV: String, profile: ModelRequestProfile) {
        self.model = model
        self.thinking = profile.sendsMimoThinkingDisabled ? ChatCompletionThinking(type: "disabled") : nil
        self.modalities = profile.sendsTextModalities ? ["text"] : nil
        self.messages = [
            ChatCompletionMessage(content: [
                .text(instruction),
                .inputAudio(data: base64WAV, format: "wav")
            ])
        ]
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
    let thinking: ChatCompletionThinking?
    let messages: [ChatCompletionMessage<String>]

    init(model: String, instruction: String, profile: ModelRequestProfile) {
        self.model = model
        self.thinking = profile.sendsMimoThinkingDisabled ? ChatCompletionThinking(type: "disabled") : nil
        self.messages = [
            ChatCompletionMessage(
                role: "system",
                content: "You are a careful speech dictation post-processor. Output only the final text."
            ),
            ChatCompletionMessage(role: "user", content: instruction)
        ]
    }
}
