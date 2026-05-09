import Foundation

public enum SSEStreamEvent: Equatable, Sendable {
    case content(String)
    case finished(String?)
    case usageOnly
    case malformedJSON(String)
    case serverError(SSEErrorInfo)
}

public struct SSEErrorInfo: Equatable, Sendable {
    public let message: String
    public let type: String?
    public let code: String?

    public init(message: String, type: String? = nil, code: String? = nil) {
        self.message = message
        self.type = type
        self.code = code
    }

    public var redactedDescription: String {
        SecretRedactor.redact([type, code, message].compactMap { $0 }.joined(separator: ": "))
    }
}

public struct ChatCompletionSSEParser: Sendable {
    private var pendingText = ""
    private var eventDataLines: [String] = []

    public init() {}

    public mutating func feed(_ data: Data) -> [SSEStreamEvent] {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return []
        }
        pendingText += text
        return drainCompleteLines()
    }

    public mutating func finish() -> [SSEStreamEvent] {
        var events = drainCompleteLines(force: true)
        if !eventDataLines.isEmpty {
            events.append(contentsOf: flushCurrentEvent())
        }
        return events
    }

    private mutating func drainCompleteLines(force: Bool = false) -> [SSEStreamEvent] {
        var events: [SSEStreamEvent] = []
        while let newlineRange = pendingText.range(of: "\n") {
            let line = String(pendingText[..<newlineRange.lowerBound])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            pendingText.removeSubrange(..<newlineRange.upperBound)
            events.append(contentsOf: processLine(line))
        }
        if force, !pendingText.isEmpty {
            let line = pendingText.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            pendingText = ""
            events.append(contentsOf: processLine(line))
        }
        return events
    }

    private mutating func processLine(_ line: String) -> [SSEStreamEvent] {
        let normalizedLine = line.trimmingCharacters(in: .whitespaces)
        if normalizedLine.isEmpty {
            return flushCurrentEvent()
        }
        guard normalizedLine.hasPrefix("data:") else {
            return []
        }
        var value = String(normalizedLine.dropFirst("data:".count))
        if value.hasPrefix(" ") {
            value.removeFirst()
        }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedValue == "[DONE]" {
            var events: [SSEStreamEvent] = []
            if !eventDataLines.isEmpty {
                events.append(contentsOf: flushCurrentEvent())
            }
            events.append(.finished("[DONE]"))
            return events
        }
        if !eventDataLines.isEmpty, trimmedValue.hasPrefix("{") {
            let events = flushCurrentEvent()
            eventDataLines.append(value)
            return events
        }
        eventDataLines.append(value)
        return []
    }

    private mutating func flushCurrentEvent() -> [SSEStreamEvent] {
        guard !eventDataLines.isEmpty else {
            return []
        }
        let payload = eventDataLines.joined(separator: "\n")
        eventDataLines.removeAll(keepingCapacity: true)

        if payload.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
            return [.finished("[DONE]")]
        }

        guard let data = payload.data(using: .utf8) else {
            return [.malformedJSON(payload)]
        }

        do {
            if let errorEnvelope = try? JSONDecoder().decode(ChatCompletionErrorEnvelope.self, from: data),
               let error = errorEnvelope.error {
                return [.serverError(SSEErrorInfo(message: error.message, type: error.type, code: error.code))]
            }
            let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: data)
            guard let choices = chunk.choices, !choices.isEmpty else {
                return [.usageOnly]
            }

            var events: [SSEStreamEvent] = []
            for choice in choices {
                if let content = choice.delta?.content, !content.isEmpty {
                    events.append(.content(content))
                }
                if let finishReason = choice.finishReason {
                    events.append(.finished(finishReason))
                }
            }
            return events.isEmpty ? [.usageOnly] : events
        } catch {
            return [.malformedJSON(payload)]
        }
    }
}

private struct ChatCompletionErrorEnvelope: Decodable {
    let error: APIError?

    struct APIError: Decodable {
        let message: String
        let type: String?
        let code: String?
    }
}

private struct ChatCompletionChunk: Decodable {
    let choices: [Choice]?

    struct Choice: Decodable {
        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct Delta: Decodable {
        let content: String?
        let reasoningContent: String?

        enum CodingKeys: String, CodingKey {
            case content
            case reasoningContent = "reasoning_content"
        }
    }
}
