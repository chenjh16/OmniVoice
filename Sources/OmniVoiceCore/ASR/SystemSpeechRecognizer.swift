import AVFoundation
import Foundation
import Speech

public final class SystemSpeechRecognizer: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func recognize(wavData: Data, options: SystemSpeechRecognitionOptions) async throws -> ASRRecognitionResult {
        let audioDurationSeconds = WAVEncoder.durationSecondsForPCM16Mono16kWAV(wavData)
        let audioURL = try writeTemporaryWAV(wavData)
        defer { try? fileManager.removeItem(at: audioURL) }

        if options.engine == .speechAnalyzer {
            if #available(macOS 26.0, *) {
                return try await recognizeWithSpeechAnalyzer(audioURL: audioURL, options: options)
            }
            throw SystemSpeechRecognitionError.speechAnalyzerUnavailable
        }
        return try await recognizeWithClassicSpeech(
            audioURL: audioURL,
            audioDurationSeconds: audioDurationSeconds,
            options: options
        )
    }

    public func makeLiveSession(
        options: SystemSpeechRecognitionOptions,
        onUpdate: @escaping @Sendable (LiveASRUpdate) -> Void
    ) async throws -> any LiveSystemSpeechRecognitionSession {
        if options.engine == .speechAnalyzer {
            if #available(macOS 26.0, *) {
                try await ensureAuthorization()
                return try await SpeechAnalyzerLiveRecognitionSession(options: options, onUpdate: onUpdate)
            }
            throw SystemSpeechRecognitionError.speechAnalyzerUnavailable
        }
        return try await makeClassicLiveSession(options: options, onUpdate: onUpdate)
    }

    private func writeTemporaryWAV(_ wavData: Data) throws -> URL {
        guard WAVEncoder.validatePCM16Mono16kWAV(wavData) else {
            throw AudioRecorderError.invalidWAV
        }
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("omnivoice-asr-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("recording.wav")
            try wavData.write(to: url, options: .atomic)
            return url
        } catch {
            throw SystemSpeechRecognitionError.temporaryFileFailed
        }
    }

    private func recognizeWithClassicSpeech(
        audioURL: URL,
        audioDurationSeconds: Double?,
        options: SystemSpeechRecognitionOptions
    ) async throws -> ASRRecognitionResult {
        try await ensureAuthorization()
        let locale = Locale(identifier: options.language.rawValue)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SystemSpeechRecognitionError.recognizerUnavailable
        }
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        let allowsAppleOnlineRecognition = try await configureClassicSpeechRequest(
            request,
            recognizer: recognizer,
            locale: locale,
            options: options
        )

        let session = ClassicSpeechFileRecognitionSession(
            recognizer: recognizer,
            request: request,
            allowsAppleOnlineRecognition: allowsAppleOnlineRecognition
        )
        return try await session.finish(
            timeoutSeconds: SystemASRFileRecognitionTimeoutPlanner.timeoutSeconds(
                audioDurationSeconds: audioDurationSeconds
            )
        )
    }

    private func makeClassicLiveSession(
        options: SystemSpeechRecognitionOptions,
        onUpdate: @escaping @Sendable (LiveASRUpdate) -> Void
    ) async throws -> any LiveSystemSpeechRecognitionSession {
        try await ensureAuthorization()
        let locale = Locale(identifier: options.language.rawValue)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SystemSpeechRecognitionError.recognizerUnavailable
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        let allowsAppleOnlineRecognition = try await configureClassicSpeechRequest(
            request,
            recognizer: recognizer,
            locale: locale,
            options: options
        )
        return ClassicSpeechLiveRecognitionSession(
            recognizer: recognizer,
            request: request,
            allowsAppleOnlineRecognition: allowsAppleOnlineRecognition,
            onUpdate: onUpdate
        )
    }

    private func configureClassicSpeechRequest(
        _ request: SFSpeechRecognitionRequest,
        recognizer: SFSpeechRecognizer,
        locale: Locale,
        options: SystemSpeechRecognitionOptions
    ) async throws -> Bool {
        request.taskHint = .dictation
        request.shouldReportPartialResults = true
        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }
        let contextualStrings = SystemASRKeywordPlanner.contextualStrings(from: options.keywordHints)
        request.contextualStrings = contextualStrings
        let allowsAppleOnlineRecognition = options.engine == .appleOnlineSpeech
        if !allowsAppleOnlineRecognition {
            guard recognizer.supportsOnDeviceRecognition else {
                throw SystemSpeechRecognitionError.onDeviceRecognitionUnavailable
            }
            request.requiresOnDeviceRecognition = true
        }
        if let languageModel = try? await prepareCustomLanguageModel(
            locale: locale,
            keywords: contextualStrings
        ) {
            request.customizedLanguageModel = languageModel
        }
        return allowsAppleOnlineRecognition
    }

    private func ensureAuthorization() async throws {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return
        case .notDetermined:
            let status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            guard status == .authorized else { throw SystemSpeechRecognitionError.notAuthorized }
        case .denied, .restricted:
            throw SystemSpeechRecognitionError.notAuthorized
        @unknown default:
            throw SystemSpeechRecognitionError.notAuthorized
        }
    }

    static func result(from result: SFSpeechRecognitionResult, allowedAppleServerRecognition: Bool) -> ASRRecognitionResult {
        let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowConfidence = result.bestTranscription.segments.compactMap { segment -> ASRSegmentAlternative? in
            guard segment.confidence > 0, segment.confidence < 0.55 else { return nil }
            return ASRSegmentAlternative(
                text: segment.substring,
                alternatives: Array(segment.alternativeSubstrings.prefix(5)),
                confidence: segment.confidence
            )
        }
        let alternatives = result.transcriptions
            .dropFirst()
            .map(\.formattedString)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return ASRRecognitionResult(
            text: text,
            lowConfidenceSegments: lowConfidence,
            alternatives: Array(alternatives.prefix(3)),
            allowedAppleServerRecognition: allowedAppleServerRecognition
        )
    }

    private func prepareCustomLanguageModel(
        locale: Locale,
        keywords: [String]
    ) async throws -> SFSpeechLanguageModel.Configuration? {
        guard !keywords.isEmpty else { return nil }
        let supportDirectory = try applicationSupportDirectory()
            .appendingPathComponent("SpeechLanguageModels", isDirectory: true)
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let version = SystemASRCustomLanguageModelCacheKey.version(
            localeIdentifier: locale.identifier,
            keywords: keywords
        )
        let assetURL = supportDirectory.appendingPathComponent("keywords-\(locale.identifier)-\(version).bin")
        let modelURL = supportDirectory.appendingPathComponent("keywords-\(locale.identifier)-\(version).lm")
        let vocabURL = supportDirectory.appendingPathComponent("keywords-\(locale.identifier)-\(version).vocab")
        if !fileManager.fileExists(atPath: assetURL.path) {
            let data = SFCustomLanguageModelData(locale: locale, identifier: "OmniVoiceKeywordHints", version: version)
            for keyword in keywords {
                data.insert(phraseCount: SFCustomLanguageModelData.PhraseCount(phrase: keyword, count: 10))
            }
            try await data.export(to: assetURL)
        }
        let configuration = SFSpeechLanguageModel.Configuration(languageModel: modelURL, vocabulary: vocabURL)
        if fileManager.fileExists(atPath: modelURL.path) {
            return configuration
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            SFSpeechLanguageModel.prepareCustomLanguageModel(for: assetURL, configuration: configuration) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        return configuration
    }

    private func applicationSupportDirectory() throws -> URL {
        let urls = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        guard let base = urls.first else { throw SystemSpeechRecognitionError.temporaryFileFailed }
        return base.appendingPathComponent(AppConstants.productName, isDirectory: true)
    }

    @available(macOS 26.0, *)
    private func recognizeWithSpeechAnalyzer(
        audioURL: URL,
        options: SystemSpeechRecognitionOptions
    ) async throws -> ASRRecognitionResult {
        try await ensureAuthorization()
        let audioFile = try AVAudioFile(forReading: audioURL)
        let runtime = try await SpeechAnalyzerRuntimePreparer.prepare(
            options: options,
            naturalAudioFormat: audioFile.processingFormat
        )
        let collector = Task { () throws -> String in
            var latest = ""
            for try await result in runtime.transcriber.results {
                latest = String(result.text.characters)
            }
            return latest.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        try await runtime.analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
        let text = try await collector.value
        guard !text.isEmpty else { throw SystemSpeechRecognitionError.noTextRecognized }
        return ASRRecognitionResult(text: text, allowedAppleServerRecognition: false)
    }
}
