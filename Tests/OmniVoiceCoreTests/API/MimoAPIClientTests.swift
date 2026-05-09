import Foundation
import ApplicationServices
import Testing
@testable import OmniVoiceCore

@Suite("MiMo API client", .serialized)
struct MimoAPIClientTests {
    @Test
    func httpErrorsAreClassifiedForDiagnostics() {
        #expect(MimoAPIError.classifiedHTTP(status: 401, preview: "bad key").diagnosticKind == "authentication_failed")
        #expect(MimoAPIError.classifiedHTTP(status: 422, preview: "audio block rejected").diagnosticKind == "model_or_audio_unsupported")
        #expect(MimoAPIError.classifiedHTTP(status: 500, preview: "server down").diagnosticKind == "http_500")
        #expect(MimoAPIError.classifiedTextCompletionHTTP(status: 401, preview: "bad key").diagnosticKind == "authentication_failed")
        #expect(MimoAPIError.classifiedTextCompletionHTTP(status: 422, preview: "model does not support chat").diagnosticKind == "text_model_unsupported")
        #expect(TextLLMFailureClassifier.isLikelyUnsupportedTextModel(
            MimoAPIError.serverError("unsupported model for chat completions")
        ))
        #expect(!TextLLMFailureClassifier.isLikelyUnsupportedTextModel(
            MimoAPIError.networkFailure("connection timed out")
        ))
        #expect(MimoAPIError.noDeltaContent.errorDescription == "No transcription delta")
        #expect(MimoAPIError.emptyFinalText.errorDescription == "Empty transcription")
    }
    @Test
    func mimoAPIClientReadsModelsAndStreamsDeltasFromOpenAICompatibleMock() async throws {
        let calls = LockedValue<[String]>([])
        MockURLProtocol.handler = { request in
            calls.withValue { $0.append(request.url?.path ?? "") }
            if request.url?.path == "/v1/models" {
                let data = Data("""
                {"data":[{"id":"mimo-v2-omni"},{"id":"mimo-v2.5"},{"id":"mimo-v2-tts"}]}
                """.utf8)
                return MockURLProtocol.response(request: request, body: data, contentType: "application/json")
            }
            if request.url?.path == "/v1/chat/completions" {
                #expect(request.httpBody?.isEmpty == false || request.httpBodyStream != nil)
                let data = Data("""
                data: {"choices":[{"delta":{"content":"Omni"},"finish_reason":null}]}

                data: {"choices":[{"delta":{"content":"Voice"},"finish_reason":null}]}

                data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

                data: [DONE]

                """.utf8)
                return MockURLProtocol.response(request: request, body: data, contentType: "text/event-stream")
            }
            throw MockURLProtocol.Error.unhandledRequest
        }
        defer { MockURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = MimoAPIClient(
            config: MimoConfig(
                baseURL: URL(string: "http://127.0.0.1:38080")!,
                apiKey: "test-key"
            ),
            session: session
        )

        let models = try await client.fetchModels()
        #expect(models == ["mimo-v2-omni", "mimo-v2.5", "mimo-v2-tts"])

        let streamed = LockedValue("")
        let result = try await client.transcribe(
            wavData: MimoAPIClient.audioProbeWAV(),
            model: .mimoV2Omni,
            instruction: "mock server test",
            recordingSeconds: 0.8,
            overallRMS: 0.02,
            allowEmptyFinalText: false,
            onDelta: { delta in streamed.withValue { $0 += delta } }
        )

        #expect(result == "OmniVoice")
        #expect(streamed.withValue { $0 } == "OmniVoice")
        #expect(calls.withValue { $0 } == ["/v1/models", "/v1/chat/completions"])
    }
    @Test
    func textCompletionStreamsDeltaContentAndIgnoresReasoningOnlyChunks() async throws {
        MockURLProtocol.handler = { request in
            if request.url?.path == "/v1/chat/completions" {
                let data = Data("""
                data: {"choices":[{"delta":{"reasoning_content":"hidden"},"finish_reason":null}]}

                data: {"choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}

                data: {"choices":[{"delta":{"content":" world"},"finish_reason":null}]}

                data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

                data: [DONE]

                """.utf8)
                return MockURLProtocol.response(request: request, body: data, contentType: "text/event-stream")
            }
            throw MockURLProtocol.Error.unhandledRequest
        }
        defer { MockURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let client = MimoAPIClient(
            config: MimoConfig(
                baseURL: URL(string: "http://127.0.0.1:38080")!,
                apiKey: "test-key"
            ),
            session: URLSession(configuration: configuration)
        )
        let streamed = LockedValue("")
        let text = try await client.completeText(
            model: .mimoV25,
            instruction: "Clean ASR draft",
            allowEmptyFinalText: false,
            onDelta: { delta in streamed.withValue { $0 += delta } }
        )

        #expect(text == "Hello world")
        #expect(streamed.withValue { $0 } == "Hello world")
    }
    @Test
    func audioProbeUsesValidLongerWAVAndAcceptsNoDeltaFailure() {
        let wav = MimoAPIClient.audioProbeWAV()
        #expect(WAVEncoder.validatePCM16Mono16kWAV(wav))
        #expect(wav.count > 20_000)
        #expect(AudioProbeSupport.accepts(error: MimoAPIError.noDeltaContent))
        #expect(AudioProbeSupport.accepts(error: MimoAPIError.emptyFinalText))
        #expect(!AudioProbeSupport.accepts(error: MimoAPIError.modelDoesNotSupportAudio(nil)))
    }
}
