import Foundation

public final class MimoAPIClient: TranscriptionClient, @unchecked Sendable {
    private let config: MimoConfig
    private let session: URLSession
    private let onDiagnostic: (@Sendable (RuntimeDiagnostic) -> Void)?

    public init(
        config: MimoConfig,
        session: URLSession = .shared,
        onDiagnostic: (@Sendable (RuntimeDiagnostic) -> Void)? = nil
    ) {
        self.config = config
        self.session = session
        self.onDiagnostic = onDiagnostic
    }

    public func fetchModels() async throws -> [String] {
        var request = URLRequest(url: endpoint("/v1/models"))
        request.httpMethod = "GET"
        applyAuthorization(to: &request)

        let (data, response) = try await session.data(for: request)
        try validateHTTP(response, preview: data.redactedPreview())
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data.map(\.id)
    }

    public func measureModelsLatency(timeout: TimeInterval = 6) async -> SourceLatencyMeasurement {
        let start = Date()
        do {
            var request = URLRequest(url: endpoint("/v1/models"))
            request.httpMethod = "GET"
            request.timeoutInterval = timeout
            applyAuthorization(to: &request)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw MimoAPIError.invalidResponse
            }
            let ids: [String]
            if (200..<300).contains(http.statusCode),
               let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data) {
                ids = decoded.data.map(\.id)
            } else {
                ids = []
            }
            return latencyMeasurement(start: start, statusCode: http.statusCode, allowedModelIDs: ids)
        } catch {
            let mapped = mapNetworkError(error)
            return SourceLatencyMeasurement(
                milliseconds: nil,
                httpStatus: nil,
                reachable: false,
                measuredAt: Date(),
                errorKind: mapped.diagnosticKind
            )
        }
    }

    public func testConnection(selectedModel: AllowedSpeechModel, runAudioProbe: Bool = false) async -> TestConnectionResult {
        do {
            let ids = try await fetchModels()
            let catalog = config.selectedPipelineModelCatalog
            let selectedAllowed = catalog.contains(selectedModel)
            let selectedObserved = ids.contains(selectedModel.rawValue)

            var probeResult: Bool?
            if runAudioProbe, selectedAllowed {
                do {
                    try await probeAudioSupport(model: selectedModel)
                    probeResult = true
                } catch MimoAPIError.modelDoesNotSupportAudio {
                    probeResult = false
                } catch {
                    if AudioProbeSupport.accepts(error: error) {
                        probeResult = true
                    } else {
                        probeResult = false
                        let preview = sanitizedMessage(for: error)
                        return TestConnectionResult(
                            selectedModel: selectedModel.rawValue,
                            modelsReachable: true,
                            selectedModelAllowed: selectedAllowed,
                            audioProbeAccepted: false,
                            audioProbeError: preview,
                            message: "Models OK; \(selectedModel.rawValue) available; audio probe failed: \(preview)"
                        )
                    }
                }
            }

            let message: String
            if selectedAllowed {
                if probeResult == true {
                    message = "Models OK; \(selectedModel.rawValue) available; audio probe accepted"
                } else if probeResult == false {
                    message = "Models OK; \(selectedModel.rawValue) available; audio probe rejected"
                } else if !selectedObserved {
                    message = "Models OK; \(selectedModel.rawValue) is configured but not exposed by the current API source"
                } else {
                    message = "Models OK; \(selectedModel.rawValue) available"
                }
            } else {
                message = "Models OK; \(selectedModel.rawValue) is not in configured model catalog"
            }
            return TestConnectionResult(
                selectedModel: selectedModel.rawValue,
                modelsReachable: true,
                selectedModelAllowed: selectedAllowed,
                audioProbeAccepted: probeResult,
                message: message
            )
        } catch {
            return TestConnectionResult(
                selectedModel: selectedModel.rawValue,
                modelsReachable: false,
                selectedModelAllowed: false,
                audioProbeAccepted: nil,
                message: sanitizedMessage(for: error)
            )
        }
    }

    public func probeAudioSupport(model: AllowedSpeechModel) async throws {
        let wav = Self.audioProbeWAV()
        _ = try await transcribe(
            wavData: wav,
            model: model,
            instruction: "This is an audio capability probe. If there is no clear speech, return an empty response. Do not explain.",
            recordingSeconds: 0.8,
            overallRMS: 0.02,
            allowEmptyFinalText: true,
            onDelta: { _ in }
        )
    }

    public static func audioProbeWAV() -> Data {
        let sampleRate = 16_000
        let count = Int(Double(sampleRate) * 0.8)
        let samples = (0..<count).map { index -> Float in
            let fadeLength = max(1, sampleRate / 20)
            let fadeIn = min(1, Float(index) / Float(fadeLength))
            let fadeOut = min(1, Float(count - index - 1) / Float(fadeLength))
            let envelope = min(fadeIn, fadeOut)
            return sin(Float(index) * 2 * .pi * 440 / Float(sampleRate)) * 0.025 * envelope
        }
        return WAVEncoder.encodePCM16WAV(samples: samples)
    }

    public func transcribe(
        wavData: Data,
        model: AllowedSpeechModel,
        instruction: String,
        recordingSeconds: Double? = nil,
        overallRMS: Float? = nil,
        allowEmptyFinalText: Bool = false,
        onDelta: @escaping @Sendable (String) -> Void,
        onPhase: @escaping @Sendable (TranscriptionRequestPhase) -> Void = { _ in }
    ) async throws -> String {
        guard config.apiKey?.isEmpty == false else {
            emit(diagnostic(stage: "transcribe", model: model, recordingSeconds: recordingSeconds, wavData: wavData, rms: overallRMS, error: .missingAPIKey))
            throw MimoAPIError.missingAPIKey
        }
        guard WAVEncoder.validatePCM16Mono16kWAV(wavData) else {
            emit(diagnostic(stage: "transcribe", model: model, recordingSeconds: recordingSeconds, wavData: wavData, rms: overallRMS, error: .invalidWAV))
            throw MimoAPIError.invalidWAV
        }

        onPhase(.preparingRequest)
        var request = URLRequest(url: endpoint("/v1/chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        applyAuthorization(to: &request)

        let payload = ChatCompletionRequest(
            model: model.rawValue,
            instruction: instruction,
            base64WAV: wavData.base64EncodedString(),
            profile: .inputAudioProfile(for: model)
        )
        request.httpBody = try JSONEncoder().encode(payload)

        return try await ChatCompletionStreamRunner(
            session: session,
            request: request,
            allowEmptyFinalText: allowEmptyFinalText,
            stages: .transcription,
            classifyHTTPError: httpError(status:preview:),
            classifyServerError: { MimoAPIError.serverError($0) },
            mapNetworkError: mapNetworkError,
            makeDiagnostic: { [self] stage, httpStatus, contentType, sseChunkCount, deltaCharacterCount, finishReason, cancellationState, error in
                self.diagnostic(
                    stage: stage,
                    model: model,
                    recordingSeconds: recordingSeconds,
                    wavData: wavData,
                    rms: overallRMS,
                    httpStatus: httpStatus,
                    contentType: contentType,
                    sseChunkCount: sseChunkCount,
                    deltaCharacterCount: deltaCharacterCount,
                    finishReason: finishReason,
                    cancellationState: cancellationState,
                    error: error
                )
            },
            validateFinalText: { finalText in
                PromptLeakageGuard.looksLikePromptLeakage(output: finalText, instruction: instruction)
                    ? .promptLeakageDetected
                    : nil
            },
            emit: emit,
            onDelta: onDelta,
            onPhase: onPhase
        ).run()
    }

    public func completeText(
        model: AllowedSpeechModel,
        instruction: String,
        allowEmptyFinalText: Bool = false,
        onDelta: @escaping @Sendable (String) -> Void,
        onPhase: @escaping @Sendable (TranscriptionRequestPhase) -> Void = { _ in }
    ) async throws -> String {
        guard config.apiKey?.isEmpty == false else {
            let error = MimoAPIError.missingAPIKey
            emit(diagnostic(stage: "text_completion", model: model, error: error))
            throw error
        }

        onPhase(.preparingRequest)
        var request = URLRequest(url: endpoint("/v1/chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        applyAuthorization(to: &request)

        let payload = TextChatCompletionRequest(
            model: model.rawValue,
            instruction: instruction,
            profile: .textProfile(for: model)
        )
        request.httpBody = try JSONEncoder().encode(payload)

        return try await ChatCompletionStreamRunner(
            session: session,
            request: request,
            allowEmptyFinalText: allowEmptyFinalText,
            stages: .textCompletion,
            classifyHTTPError: MimoAPIError.classifiedTextCompletionHTTP(status:preview:),
            classifyServerError: TextLLMFailureClassifier.classifiedServerError,
            mapNetworkError: mapNetworkError,
            makeDiagnostic: { [self] stage, httpStatus, contentType, sseChunkCount, deltaCharacterCount, finishReason, cancellationState, error in
                self.diagnostic(
                    stage: stage,
                    model: model,
                    httpStatus: httpStatus,
                    contentType: contentType,
                    sseChunkCount: sseChunkCount,
                    deltaCharacterCount: deltaCharacterCount,
                    finishReason: finishReason,
                    cancellationState: cancellationState,
                    error: error
                )
            },
            validateFinalText: { _ in nil },
            emit: emit,
            onDelta: onDelta,
            onPhase: onPhase
        ).run()
    }

    private func endpoint(_ path: String) -> URL {
        var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false)!
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, suffix].filter { !$0.isEmpty }.joined(separator: "/")
        return components.url!
    }

    private func latencyMeasurement(start: Date, statusCode: Int, allowedModelIDs: [String]) -> SourceLatencyMeasurement {
        SourceLatencyMeasurement(
            milliseconds: max(1, Int(Date().timeIntervalSince(start) * 1000)),
            httpStatus: statusCode,
            reachable: (200..<300).contains(statusCode),
            allowedModelIDs: allowedModelIDs,
            measuredAt: Date(),
            errorKind: (200..<300).contains(statusCode) ? nil : "http_\(statusCode)"
        )
    }

    private func applyAuthorization(to request: inout URLRequest) {
        guard let apiKey = config.apiKey, !apiKey.isEmpty else { return }
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    private func validateHTTP(_ response: URLResponse, preview: String?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw MimoAPIError.invalidResponse
        }
        if !(200..<300).contains(http.statusCode) {
            throw httpError(status: http.statusCode, preview: preview)
        }
    }

    private func httpError(status: Int, preview: String?) -> MimoAPIError {
        MimoAPIError.classifiedHTTP(status: status, preview: preview)
    }

    private func sanitizedMessage(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return localized
        }
        return "Connection failed"
    }

    private func mapNetworkError(_ error: Error) -> MimoAPIError {
        if let urlError = error as? URLError {
            if urlError.code == .cancelled {
                return .cancelled
            }
            return .networkFailure("Network \(urlError.code.rawValue): \(urlError.localizedDescription)")
        }
        if let mimoError = error as? MimoAPIError {
            return mimoError
        }
        return .networkFailure("Network failed: \(error.localizedDescription)")
    }

    private func diagnostic(
        stage: String,
        model: AllowedSpeechModel,
        recordingSeconds: Double? = nil,
        wavData: Data? = nil,
        rms: Float? = nil,
        httpStatus: Int? = nil,
        contentType: String? = nil,
        sseChunkCount: Int = 0,
        deltaCharacterCount: Int = 0,
        finishReason: String? = nil,
        cancellationState: String? = nil,
        error: MimoAPIError? = nil
    ) -> RuntimeDiagnostic {
        RuntimeDiagnostic(
            stage: stage,
            host: config.baseURL.host ?? config.baseURL.absoluteString,
            model: model.rawValue,
            recordingSeconds: recordingSeconds,
            wavBytes: wavData?.count,
            rms: rms,
            httpStatus: httpStatus,
            contentType: contentType,
            sseChunkCount: sseChunkCount,
            deltaCharacterCount: deltaCharacterCount,
            finishReason: finishReason,
            cancellationState: cancellationState,
            errorKind: error?.diagnosticKind,
            errorPreview: error?.diagnosticPreview
        )
    }

    private func emit(_ diagnostic: RuntimeDiagnostic) {
        RuntimeDiagnostic.log(diagnostic)
        onDiagnostic?(diagnostic)
    }
}
