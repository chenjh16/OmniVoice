import Foundation

public struct WAVFormat: Equatable, Sendable {
    public let sampleRate: Int
    public let channelCount: Int
    public let bitsPerSample: Int

    public static let mono16kPCM16 = WAVFormat(sampleRate: 16_000, channelCount: 1, bitsPerSample: 16)
}

public enum WAVEncoder {
    public static func encodePCM16WAV(samples: [Float], format: WAVFormat = .mono16kPCM16) -> Data {
        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let scaled = clamped < 0 ? clamped * 32768.0 : clamped * 32767.0
            var value = Int16(scaled).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        return wrapPCMDataAsWAV(pcm, format: format)
    }

    public static func wrapPCMDataAsWAV(_ pcmData: Data, format: WAVFormat = .mono16kPCM16) -> Data {
        let byteRate = format.sampleRate * format.channelCount * format.bitsPerSample / 8
        let blockAlign = format.channelCount * format.bitsPerSample / 8
        let dataSize = UInt32(pcmData.count)
        let riffSize = UInt32(36 + pcmData.count)

        var data = Data()
        data.appendASCII("RIFF")
        data.appendLE(riffSize)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLE(UInt32(16))
        data.appendLE(UInt16(1))
        data.appendLE(UInt16(format.channelCount))
        data.appendLE(UInt32(format.sampleRate))
        data.appendLE(UInt32(byteRate))
        data.appendLE(UInt16(blockAlign))
        data.appendLE(UInt16(format.bitsPerSample))
        data.appendASCII("data")
        data.appendLE(dataSize)
        data.append(pcmData)
        return data
    }

    public static func validatePCM16Mono16kWAV(_ data: Data) -> Bool {
        guard data.count >= 44,
              String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE",
              String(data: data[12..<16], encoding: .ascii) == "fmt ",
              String(data: data[36..<40], encoding: .ascii) == "data" else {
            return false
        }
        let audioFormat = data.uint16LE(at: 20)
        let channels = data.uint16LE(at: 22)
        let sampleRate = data.uint32LE(at: 24)
        let bitsPerSample = data.uint16LE(at: 34)
        let dataSize = data.uint32LE(at: 40)
        return audioFormat == 1 &&
            channels == 1 &&
            sampleRate == 16_000 &&
            bitsPerSample == 16 &&
            Int(dataSize) == data.count - 44
    }

    public static func decodePCM16Mono16kSamples(_ data: Data) -> [Float]? {
        guard validatePCM16Mono16kWAV(data) else { return nil }
        let pcmStart = 44
        let pcmBytes = data.count - pcmStart
        guard pcmBytes % 2 == 0 else { return nil }

        var samples = [Float]()
        samples.reserveCapacity(pcmBytes / 2)
        var offset = pcmStart
        while offset < data.count {
            let raw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            let value = Int16(bitPattern: raw)
            if value < 0 {
                samples.append(Float(value) / 32_768.0)
            } else {
                samples.append(Float(value) / 32_767.0)
            }
            offset += 2
        }
        return samples
    }

    public static func durationSecondsForPCM16Mono16kWAV(_ data: Data) -> Double? {
        guard validatePCM16Mono16kWAV(data) else { return nil }
        return Double(data.count - 44) / 2.0 / Double(WAVFormat.mono16kPCM16.sampleRate)
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(string.data(using: .ascii)!)
    }

    mutating func appendLE(_ value: UInt16) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendLE(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    func uint16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset]) |
            (UInt32(self[offset + 1]) << 8) |
            (UInt32(self[offset + 2]) << 16) |
            (UInt32(self[offset + 3]) << 24)
    }
}
