import Foundation
import OmniVoiceCore

public final class WAVReplayRecordingSource: ReplayRecordingSource, @unchecked Sendable {
    public var onRMSLevel: (@Sendable (Float) -> Void)?
    public var onSampleChunk: (@Sendable (AudioSampleChunk) -> Void)?

    private let sourceSamples: [Float]
    private let chunkFrameCount: Int
    private let replaySpeed: Double
    private let lock = NSLock()
    private var replayTask: Task<Void, Never>?
    private var capturedSamples: [Float] = []
    private var sumSquares: Double = 0
    private var sampleCount: Int = 0
    private var envelope: Float = 0
    private var recording = false
    private var replayCompleted = false

    public init(
        wavData: Data,
        chunkFrameCount: Int = 1_024,
        replaySpeed: Double = 1.0
    ) throws {
        guard let samples = WAVEncoder.decodePCM16Mono16kSamples(wavData) else {
            throw AudioRecorderError.invalidWAV
        }
        sourceSamples = samples
        self.chunkFrameCount = max(1, chunkFrameCount)
        if replaySpeed.isFinite, replaySpeed > 0 {
            self.replaySpeed = replaySpeed
        } else {
            self.replaySpeed = 1.0
        }
    }

    public var isRecording: Bool {
        lock.withLock { recording }
    }

    public var isReplayCompleted: Bool {
        lock.withLock { replayCompleted }
    }

    public func start() throws {
        lock.lock()
        if recording {
            lock.unlock()
            throw AudioRecorderError.alreadyRecording
        }
        capturedSamples.removeAll(keepingCapacity: true)
        sumSquares = 0
        sampleCount = 0
        envelope = 0
        replayCompleted = false
        recording = true
        lock.unlock()

        replayTask = Task { [weak self] in
            await self?.replayLoop()
        }
    }

    public func stop(
        minimumDurationSeconds: Double = RecordingValidator.minimumDurationSeconds,
        validationPolicy: RecordingValidationPolicy = .voiceGated
    ) throws -> AudioRecordingResult {
        replayTask?.cancel()
        replayTask = nil

        let snapshot = lock.withLock {
            let wasRecording = recording
            recording = false
            let snapshot = (wasRecording, capturedSamples, sumSquares, sampleCount)
            capturedSamples.removeAll(keepingCapacity: true)
            sumSquares = 0
            sampleCount = 0
            envelope = 0
            return snapshot
        }

        guard snapshot.0 else { throw AudioRecorderError.notRecording }
        guard !snapshot.1.isEmpty else { throw AudioRecorderError.noSamples }

        let duration = Double(snapshot.3) / Double(WAVFormat.mono16kPCM16.sampleRate)
        let rms = Float(sqrt(snapshot.2 / Double(max(snapshot.3, 1))))
        try RecordingResultValidator.validate(
            durationSeconds: duration,
            overallRMS: rms,
            minimumDurationSeconds: minimumDurationSeconds,
            policy: validationPolicy
        )

        let wav = WAVEncoder.encodePCM16WAV(samples: snapshot.1)
        guard WAVEncoder.validatePCM16Mono16kWAV(wav) else {
            throw AudioRecorderError.invalidWAV
        }
        return AudioRecordingResult(wavData: wav, durationSeconds: duration, overallRMS: rms)
    }

    public func cancel() {
        replayTask?.cancel()
        replayTask = nil
        lock.withLock {
            recording = false
            capturedSamples.removeAll(keepingCapacity: true)
            sumSquares = 0
            sampleCount = 0
            envelope = 0
            replayCompleted = false
        }
    }

    public func waitUntilReplayFinished() async {
        let task = lock.withLock { replayTask }
        await task?.value
    }

    private func replayLoop() async {
        var index = 0
        while index < sourceSamples.count {
            if Task.isCancelled { return }
            let end = min(index + chunkFrameCount, sourceSamples.count)
            let frameCount = end - index
            emitChunk(Array(sourceSamples[index..<end]))
            index = end

            let seconds = Double(frameCount) / Double(WAVFormat.mono16kPCM16.sampleRate)
            let delaySeconds = seconds / replaySpeed
            if delaySeconds > 0 {
                let nanoseconds = UInt64(delaySeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
        lock.withLock {
            replayCompleted = true
        }
    }

    private func emitChunk(_ chunk: [Float]) {
        guard !chunk.isEmpty else { return }
        var bufferSumSquares: Double = 0
        for sample in chunk {
            bufferSumSquares += Double(sample * sample)
        }
        let instantRMS = Float(sqrt(bufferSumSquares / Double(chunk.count)))

        let level = lock.withLock {
            guard recording else { return Float(0) }
            capturedSamples.append(contentsOf: chunk)
            sumSquares += bufferSumSquares
            sampleCount += chunk.count
            let attack: Float = 0.55
            let release: Float = 0.42
            let smoothing = instantRMS > envelope ? attack : release
            envelope = envelope + (instantRMS - envelope) * smoothing
            return min(max(envelope * 20, 0), 1)
        }
        onRMSLevel?(level)
        onSampleChunk?(AudioSampleChunk(samples: chunk, sampleRate: Double(WAVFormat.mono16kPCM16.sampleRate)))
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
