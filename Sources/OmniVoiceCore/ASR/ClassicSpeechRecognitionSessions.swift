import AVFoundation
import Foundation
import Speech

final class ClassicSpeechFileRecognitionSession: @unchecked Sendable {
    private let request: SFSpeechURLRecognitionRequest
    private let allowsAppleOnlineRecognition: Bool
    private let lock = NSLock()
    private var task: SFSpeechRecognitionTask?
    private var latestResult: SFSpeechRecognitionResult?
    private var completion: CheckedContinuation<ASRRecognitionResult, Error>?
    private var completedResult: Result<ASRRecognitionResult, Error>?
    private var timeoutTask: Task<Void, Never>?

    init(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechURLRecognitionRequest,
        allowsAppleOnlineRecognition: Bool
    ) {
        self.request = request
        self.allowsAppleOnlineRecognition = allowsAppleOnlineRecognition
        self.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handleRecognition(result: result, error: error)
        }
    }

    func finish(timeoutSeconds: TimeInterval) async throws -> ASRRecognitionResult {
        try await withCheckedThrowingContinuation { continuation in
            let immediate = lock.withLock { () -> Result<ASRRecognitionResult, Error>? in
                if let completedResult {
                    return completedResult
                }
                completion = continuation
                return nil
            }
            if let immediate {
                continuation.resume(with: immediate)
                return
            }

            let timeoutTask = Task { [weak self] in
                let nanoseconds = UInt64(max(timeoutSeconds, 0.1) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                self?.completeWithLatestOrError(
                    SystemSpeechRecognitionError.recognitionFailed("System speech recognition timed out")
                )
                self?.task?.cancel()
            }
            let shouldKeepTimeoutTask = lock.withLock { () -> Bool in
                guard completedResult == nil else { return false }
                self.timeoutTask = timeoutTask
                return true
            }
            if !shouldKeepTimeoutTask {
                timeoutTask.cancel()
            }
        }
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            lock.withLock {
                latestResult = result
            }
            if result.isFinal {
                complete(.success(ClassicSpeechRecognitionCompletionResolver.finalResult(
                    from: result,
                    allowedAppleServerRecognition: allowedAppleServerRecognition
                )))
            }
            return
        }
        if let error {
            completeWithLatestOrError(SystemSpeechRecognitionError.recognitionFailed(error.localizedDescription))
        }
    }

    private var allowedAppleServerRecognition: Bool {
        allowsAppleOnlineRecognition && !request.requiresOnDeviceRecognition
    }

    private func completeWithLatestOrError(_ error: Error) {
        let latest = lock.withLock { latestResult }
        complete(ClassicSpeechRecognitionCompletionResolver.resultOrError(
            latest,
            allowedAppleServerRecognition: allowedAppleServerRecognition,
            fallback: error
        ))
    }

    private func complete(_ result: Result<ASRRecognitionResult, Error>) {
        let completionState = lock.withLock { () -> (CheckedContinuation<ASRRecognitionResult, Error>?, Task<Void, Never>?) in
            guard completedResult == nil else { return (nil, nil) }
            completedResult = result
            let current = completion
            completion = nil
            let currentTimeoutTask = timeoutTask
            timeoutTask = nil
            return (current, currentTimeoutTask)
        }
        completionState.1?.cancel()
        completionState.0?.resume(with: result)
    }

}

final class ClassicSpeechLiveRecognitionSession: LiveSystemSpeechRecognitionSession, @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    private var task: SFSpeechRecognitionTask?
    private let allowsAppleOnlineRecognition: Bool
    private let appendQueue = DispatchQueue(label: "dev.omnivoice.live-asr.classic.append")
    private let lock = NSLock()
    private var latestResult: SFSpeechRecognitionResult?
    private var completion: CheckedContinuation<ASRRecognitionResult, Error>?
    private var completedResult: Result<ASRRecognitionResult, Error>?
    private var finishing = false
    private var cancelled = false

    init(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        allowsAppleOnlineRecognition: Bool,
        onUpdate: @escaping @Sendable (LiveASRUpdate) -> Void
    ) {
        self.request = request
        self.allowsAppleOnlineRecognition = allowsAppleOnlineRecognition
        self.task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handleRecognition(result: result, error: error, onUpdate: onUpdate)
        }
    }

    func append(_ chunk: AudioSampleChunk) {
        guard let buffer = Self.buffer(from: chunk) else { return }
        appendQueue.async { [weak self] in
            guard let self, !self.isFinished else { return }
            self.request.append(buffer)
        }
    }

    func finish() async throws -> ASRRecognitionResult {
        appendQueue.async { [weak self] in
            guard let self, !self.isFinished else { return }
            self.request.endAudio()
        }
        return try await withCheckedThrowingContinuation { continuation in
            let immediate = lock.withLock { () -> Result<ASRRecognitionResult, Error>? in
                finishing = true
                if let completedResult {
                    return completedResult
                }
                completion = continuation
                return nil
            }
            if let immediate {
                continuation.resume(with: immediate)
                return
            }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                self?.completeWithLatestOrError(SystemSpeechRecognitionError.recognitionFailed("Live speech recognition timed out"))
            }
        }
    }

    func cancel() {
        let shouldCancel = lock.withLock { () -> Bool in
            guard !cancelled else { return false }
            cancelled = true
            return true
        }
        guard shouldCancel else { return }
        appendQueue.async { [weak self] in
            self?.request.endAudio()
            self?.task?.cancel()
        }
        complete(.failure(SystemSpeechRecognitionError.recognitionFailed("Live speech recognition cancelled")))
    }

    private var isFinished: Bool {
        lock.withLock { cancelled || completedResult != nil }
    }

    private func handleRecognition(
        result: SFSpeechRecognitionResult?,
        error: Error?,
        onUpdate: @escaping @Sendable (LiveASRUpdate) -> Void
    ) {
        if let result {
            lock.withLock {
                latestResult = result
            }
            let text = ClassicSpeechRecognitionCompletionResolver.trimmedText(from: result)
            if !text.isEmpty {
                onUpdate(LiveASRUpdate(text: text, isFinal: result.isFinal))
            }
            if result.isFinal {
                complete(.success(ClassicSpeechRecognitionCompletionResolver.finalResult(
                    from: result,
                    allowedAppleServerRecognition: allowedAppleServerRecognition
                )))
            }
            return
        }
        if let error {
            completeWithLatestOrError(SystemSpeechRecognitionError.recognitionFailed(error.localizedDescription))
        }
    }

    private var allowedAppleServerRecognition: Bool {
        allowsAppleOnlineRecognition && !request.requiresOnDeviceRecognition
    }

    private func completeWithLatestOrError(_ error: Error) {
        let latest = lock.withLock { latestResult }
        complete(ClassicSpeechRecognitionCompletionResolver.resultOrError(
            latest,
            allowedAppleServerRecognition: allowedAppleServerRecognition,
            fallback: error
        ))
    }

    private func complete(_ result: Result<ASRRecognitionResult, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<ASRRecognitionResult, Error>? in
            guard completedResult == nil else { return nil }
            completedResult = result
            let current = completion
            completion = nil
            return current
        }
        continuation?.resume(with: result)
    }

    static func buffer(from chunk: AudioSampleChunk) -> AVAudioPCMBuffer? {
        guard !chunk.samples.isEmpty,
              chunk.sampleRate.isFinite,
              chunk.sampleRate > 0,
              let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: chunk.sampleRate,
                channels: 1,
                interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(chunk.samples.count)
              ) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(chunk.samples.count)
        guard let target = buffer.floatChannelData?[0] else { return nil }
        chunk.samples.withUnsafeBufferPointer { pointer in
            if let baseAddress = pointer.baseAddress {
                target.update(from: baseAddress, count: pointer.count)
            }
        }
        return buffer
    }
}

enum ClassicSpeechRecognitionCompletionResolver {
    static func trimmedText(from result: SFSpeechRecognitionResult) -> String {
        result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func resultOrError(
        _ latest: SFSpeechRecognitionResult?,
        allowedAppleServerRecognition: Bool,
        fallback error: Error
    ) -> Result<ASRRecognitionResult, Error> {
        guard let latest, !trimmedText(from: latest).isEmpty else {
            return .failure(error)
        }
        return .success(finalResult(
            from: latest,
            allowedAppleServerRecognition: allowedAppleServerRecognition
        ))
    }

    static func finalResult(
        from result: SFSpeechRecognitionResult,
        allowedAppleServerRecognition: Bool
    ) -> ASRRecognitionResult {
        SystemSpeechRecognizer.result(from: result, allowedAppleServerRecognition: allowedAppleServerRecognition)
    }
}
