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
        #expect(MimoAPIError.promptLeakageDetected.diagnosticKind == "prompt_leakage_detected")
        #expect(MimoAPIError.promptLeakageDetected.errorDescription == "No reliable speech recognized")
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
        let phases = LockedValue<[TranscriptionRequestPhase]>([])
        let result = try await client.transcribe(
            wavData: MimoAPIClient.audioProbeWAV(),
            model: .mimoV2Omni,
            instruction: "mock server test",
            recordingSeconds: 0.8,
            overallRMS: 0.02,
            allowEmptyFinalText: false,
            onDelta: { delta in streamed.withValue { $0 += delta } },
            onPhase: { phase in phases.withValue { $0.append(phase) } }
        )

        #expect(result == "OmniVoice")
        #expect(streamed.withValue { $0 } == "OmniVoice")
        #expect(calls.withValue { $0 } == ["/v1/models", "/v1/chat/completions"])
        #expect(phases.withValue { $0 } == [
            .preparingRequest,
            .connecting,
            .responseReceived,
            .waitingForFirstDelta,
            .streaming,
            .completed
        ])
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
        let phases = LockedValue<[TranscriptionRequestPhase]>([])
        let text = try await client.completeText(
            model: .mimoV25,
            instruction: "Clean ASR draft",
            allowEmptyFinalText: false,
            onDelta: { delta in streamed.withValue { $0 += delta } },
            onPhase: { phase in phases.withValue { $0.append(phase) } }
        )

        #expect(text == "Hello world")
        #expect(streamed.withValue { $0 } == "Hello world")
        #expect(phases.withValue { $0 } == [
            .preparingRequest,
            .connecting,
            .responseReceived,
            .waitingForFirstDelta,
            .streaming,
            .completed
        ])
    }
    @Test
    func directAudioRejectsPromptLeakageLikeFinalText() async throws {
        let instruction = TranscriptionInstructionBuilder.instruction(style: .rewrite)
        MockURLProtocol.handler = { request in
            if request.url?.path == "/v1/chat/completions" {
                let escaped = instruction
                    .split(separator: "\n")
                    .prefix(4)
                    .joined(separator: "\\n")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                let data = Data("""
                data: {"choices":[{"delta":{"content":"\(escaped)"},"finish_reason":null}]}

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

        do {
            _ = try await client.transcribe(
                wavData: MimoAPIClient.audioProbeWAV(),
                model: .mimoV25,
                instruction: instruction,
                recordingSeconds: 0.8,
                overallRMS: 0.02,
                onDelta: { _ in }
            )
            Issue.record("Expected prompt leakage to be rejected")
        } catch let error as MimoAPIError {
            #expect(error == .promptLeakageDetected)
        } catch {
            Issue.record("Expected MimoAPIError.promptLeakageDetected, got \(error)")
        }
    }

    @Test
    func promptLeakageGuardKeepsNormalShortKeywordDictation() {
        let instruction = TranscriptionInstructionBuilder.instruction(style: .concise)
        #expect(PromptLeakageGuard.looksLikePromptLeakage(
            output: "只输出最终文本。",
            instruction: instruction
        ))
        #expect(PromptLeakageGuard.looksLikePromptLeakage(
            output: "默认输出简体中文；如果音频主要是英文，输出英文。",
            instruction: instruction
        ))
        #expect(!PromptLeakageGuard.looksLikePromptLeakage(
            output: "OpenAI、Claude、Gemini 和 Qwen 都要放到关键词里。",
            instruction: instruction
        ))
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
