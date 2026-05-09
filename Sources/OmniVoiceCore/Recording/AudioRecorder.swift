import AVFoundation
import Foundation

public struct AudioRecordingResult: Sendable {
    public let wavData: Data
    public let durationSeconds: Double
    public let overallRMS: Float

    public init(wavData: Data, durationSeconds: Double, overallRMS: Float) {
        self.wavData = wavData
        self.durationSeconds = durationSeconds
        self.overallRMS = overallRMS
    }
}

public struct AudioSampleChunk: Sendable {
    public let samples: [Float]
    public let sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }
}

public protocol RecordingSource: AnyObject, Sendable {
    var onRMSLevel: (@Sendable (Float) -> Void)? { get set }
    var onSampleChunk: (@Sendable (AudioSampleChunk) -> Void)? { get set }
    var isRecording: Bool { get }
    func start() throws
    func stop(
        minimumDurationSeconds: Double,
        validationPolicy: RecordingValidationPolicy
    ) throws -> AudioRecordingResult
    func cancel()
}

public extension RecordingSource {
    func stop(minimumDurationSeconds: Double) throws -> AudioRecordingResult {
        try stop(minimumDurationSeconds: minimumDurationSeconds, validationPolicy: .voiceGated)
    }
}

public enum AudioRecorderError: LocalizedError, Sendable {
    case alreadyRecording
    case notRecording
    case noInputFormat
    case noSamples
    case tooShort
    case tooQuiet
    case conversionFailed
    case invalidWAV

    public var errorDescription: String? {
        switch self {
        case .alreadyRecording: return "Already recording"
        case .notRecording: return "Not recording"
        case .noInputFormat: return "No microphone input"
        case .noSamples: return "No audio captured"
        case .tooShort: return "录音过短"
        case .tooQuiet: return "未检测到有效语音"
        case .conversionFailed: return "Audio conversion failed"
        case .invalidWAV: return "Invalid WAV"
        }
    }
}

public final class AudioRecorder: RecordingSource, @unchecked Sendable {
    public var onRMSLevel: (@Sendable (Float) -> Void)?
    public var onSampleChunk: (@Sendable (AudioSampleChunk) -> Void)?

    private var engine: AVAudioEngine?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate: Double = 0
    private var envelope: Float = 0
    private var sumSquares: Double = 0
    private var sampleCount: Int = 0
    private var startDate: Date?
    private var recording = false

    public init() {}

    public var isRecording: Bool {
        lock.withLock { recording }
    }

    public func start() throws {
        let newEngine = AVAudioEngine()
        lock.lock()
        if recording {
            lock.unlock()
            throw AudioRecorderError.alreadyRecording
        }
        samples.removeAll(keepingCapacity: true)
        sumSquares = 0
        sampleCount = 0
        envelope = 0
        startDate = Date()
        recording = true
        engine = newEngine
        lock.unlock()

        let input = newEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            cancel()
            throw AudioRecorderError.noInputFormat
        }
        sampleRate = format.sampleRate

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            self?.capture(buffer: buffer)
        }

        newEngine.prepare()
        do {
            try newEngine.start()
        } catch {
            cancel()
            throw error
        }
    }

    public func stop(
        minimumDurationSeconds: Double = RecordingValidator.minimumDurationSeconds,
        validationPolicy: RecordingValidationPolicy = .voiceGated
    ) throws -> AudioRecordingResult {
        let snapshot = stopAndSnapshot()
        guard snapshot.wasRecording else { throw AudioRecorderError.notRecording }
        guard !snapshot.samples.isEmpty else { throw AudioRecorderError.noSamples }

        let duration = Double(snapshot.samples.count) / snapshot.sampleRate
        let rms = Float(sqrt(snapshot.sumSquares / Double(max(snapshot.sampleCount, 1))))
        let validation = RecordingValidator.validate(
            durationSeconds: duration,
            overallRMS: rms,
            minimumDurationSeconds: minimumDurationSeconds,
            policy: validationPolicy
        )
        switch validation.status {
        case .valid:
            break
        case .tooShort:
            throw AudioRecorderError.tooShort
        case .tooQuiet:
            throw AudioRecorderError.tooQuiet
        }

        let wav = try convertToMono16kPCM16WAV(samples: snapshot.samples, sourceSampleRate: snapshot.sampleRate)
        guard WAVEncoder.validatePCM16Mono16kWAV(wav) else {
            throw AudioRecorderError.invalidWAV
        }
        return AudioRecordingResult(wavData: wav, durationSeconds: duration, overallRMS: rms)
    }

    public func cancel() {
        _ = stopAndSnapshot()
    }

    private func stopAndSnapshot() -> (wasRecording: Bool, samples: [Float], sampleRate: Double, sumSquares: Double, sampleCount: Int) {
        let engineToStop = lock.withLock {
            let current = engine
            engine = nil
            return current
        }
        if let engineToStop {
            engineToStop.inputNode.removeTap(onBus: 0)
            engineToStop.stop()
        }

        return lock.withLock {
            let wasRecording = recording
            recording = false
            let snapshot = (wasRecording, samples, sampleRate, sumSquares, sampleCount)
            samples.removeAll(keepingCapacity: true)
            sumSquares = 0
            sampleCount = 0
            startDate = nil
            envelope = 0
            return snapshot
        }
    }

    private func capture(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0 else { return }

        var mono = [Float]()
        mono.reserveCapacity(frames)
        var bufferSumSquares: Double = 0

        for frame in 0..<frames {
            var mixed: Float = 0
            for channel in 0..<channels {
                mixed += channelData[channel][frame]
            }
            mixed /= Float(channels)
            mono.append(mixed)
            bufferSumSquares += Double(mixed * mixed)
        }

        let instantRMS = Float(sqrt(bufferSumSquares / Double(frames)))
        lock.lock()
        samples.append(contentsOf: mono)
        sumSquares += bufferSumSquares
        sampleCount += frames
        let attack: Float = 0.55
        let release: Float = 0.42
        let smoothing = instantRMS > envelope ? attack : release
        envelope = envelope + (instantRMS - envelope) * smoothing
        let level = min(max(envelope * 20, 0), 1)
        lock.unlock()

        onRMSLevel?(level)
        onSampleChunk?(AudioSampleChunk(samples: mono, sampleRate: buffer.format.sampleRate))
    }

    private func convertToMono16kPCM16WAV(samples: [Float], sourceSampleRate: Double) throws -> Data {
        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sourceSampleRate,
            channels: 1,
            interleaved: false
        ),
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ),
        let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw AudioRecorderError.conversionFailed
        }

        sourceBuffer.frameLength = AVAudioFrameCount(samples.count)
        let sourcePointer = sourceBuffer.floatChannelData![0]
        for (index, sample) in samples.enumerated() {
            sourcePointer[index] = sample
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioRecorderError.conversionFailed
        }

        let ratio = 16_000 / sourceSampleRate
        let targetCapacity = AVAudioFrameCount(ceil(Double(samples.count) * ratio) + 1_024)
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetCapacity) else {
            throw AudioRecorderError.conversionFailed
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: targetBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }
        guard conversionError == nil, status != .error else {
            throw AudioRecorderError.conversionFailed
        }

        let frames = Int(targetBuffer.frameLength)
        guard frames > 0, let int16Data = targetBuffer.int16ChannelData?[0] else {
            throw AudioRecorderError.conversionFailed
        }
        let pcmData = Data(bytes: int16Data, count: frames * MemoryLayout<Int16>.size)
        return WAVEncoder.wrapPCMDataAsWAV(pcmData, format: .mono16kPCM16)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
