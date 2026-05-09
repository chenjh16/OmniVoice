import Foundation
import ApplicationServices
import Testing
@testable import OmniVoiceCore

@Suite("SSE parser")
struct SSEParserTests {
    @Test
    func sseParserHandlesContentUsageAndDone() {
        var parser = ChatCompletionSSEParser()
        let stream = """
        data: {"choices":[{"delta":{"content":"你好"},"finish_reason":null}]}

        data: {"usage":{"total_tokens":3},"choices":[]}

        data: [DONE]

        """
        let events = parser.feed(Data(stream.utf8))
        #expect(events == [.content("你好"), .usageOnly, .finished("[DONE]")])
    }
    @Test
    func sseParserHandlesAdjacentDataLinesWithoutBlankSeparators() {
        var parser = ChatCompletionSSEParser()
        let stream = """
        data: {"id":"x","object":"chat.completion.chunk","created":1777911272,"model":"mimo-v2-omni","choices":[{"index":0,"delta":{"role":"assistant","content":"","reasoning_content":null,"tool_calls":null},"logprobs":null,"finish_reason":null}]}
        data: {"id":"x","object":"chat.completion.chunk","created":1777911273,"model":"mimo-v2-omni","choices":[{"index":0,"delta":{"content":"你好"},"finish_reason":null}]}
        data: {"id":"x","object":"chat.completion.chunk","created":1777911274,"model":"mimo-v2-omni","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}
        data: [DONE]
        """
        var events = parser.feed(Data(stream.utf8))
        events.append(contentsOf: parser.finish())
        #expect(events == [.usageOnly, .content("你好"), .finished("stop"), .finished("[DONE]")])
    }
    @Test
    func sseParserHandlesBadJSONAndSplitChunks() {
        var parser = ChatCompletionSSEParser()
        #expect(parser.feed(Data("data: {\"choices\":[{\"delta\":{\"content\":\"Py".utf8)) == [])
        #expect(
            parser.feed(Data("thon\"},\"finish_reason\":\"stop\"}]}\n\n".utf8)) == [.content("Python"), .finished("stop")]
        )

        var badParser = ChatCompletionSSEParser()
        #expect(badParser.feed(Data("data: {bad-json}\n\n".utf8)) == [.malformedJSON("{bad-json}")])
    }
    @Test
    func sseParserHandlesServerErrorPayload() {
        var parser = ChatCompletionSSEParser()
        var events = parser.feed(Data("""
        data: {"error":{"message":"model does not support input_audio","type":"invalid_request_error","code":"unsupported_audio"}}

        """.utf8))
        events.append(contentsOf: parser.finish())
        #expect(events == [.serverError(SSEErrorInfo(message: "model does not support input_audio", type: "invalid_request_error", code: "unsupported_audio"))])
    }
}
