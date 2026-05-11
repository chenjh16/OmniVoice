import AVFoundation
import Foundation

enum AudioBufferConverter {
    static func monoFloatBuffer(samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer? {
        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ),
        let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ),
        let sourcePointer = sourceBuffer.floatChannelData?[0] else {
            return nil
        }

        sourceBuffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            sourcePointer[index] = sample
        }
        return sourceBuffer
    }

    static func convertSingleBuffer(
        _ sourceBuffer: AVAudioPCMBuffer,
        to targetFormat: AVAudioFormat,
        additionalCapacityFrames: AVAudioFrameCount = 1_024
    ) -> AVAudioPCMBuffer? {
        if formatsMatch(sourceBuffer.format, targetFormat) {
            return sourceBuffer
        }
        guard let converter = AVAudioConverter(from: sourceBuffer.format, to: targetFormat) else {
            return nil
        }
        let ratio = targetFormat.sampleRate / max(sourceBuffer.format.sampleRate, 1)
        let frameCapacity = AVAudioFrameCount(ceil(Double(sourceBuffer.frameLength) * ratio)) + additionalCapacityFrames
        guard let targetBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: max(frameCapacity, 1)
        ) else {
            return nil
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
        guard conversionError == nil else { return nil }
        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            return targetBuffer.frameLength > 0 ? targetBuffer : nil
        case .error:
            return nil
        @unknown default:
            return nil
        }
    }

    static func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        lhs.commonFormat == rhs.commonFormat &&
            lhs.sampleRate == rhs.sampleRate &&
            lhs.channelCount == rhs.channelCount &&
            lhs.isInterleaved == rhs.isInterleaved
    }
}
