import AVFoundation
import Foundation

// MARK: - AudioResampler

/// Resamples 16-bit mono PCM between sample rates (used once at MP4 mux).
enum AudioResampler {

    static func resamplePCM16Mono(
        _ data: Data,
        from sourceRate: Double,
        to targetRate: Double
    ) -> Data? {
        guard sourceRate > 0, targetRate > 0, !data.isEmpty else { return nil }
        if sourceRate == targetRate { return data }

        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sourceRate,
            channels: 1,
            interleaved: true
        ),
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetRate,
            channels: 1,
            interleaved: true
        ),
        let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            return nil
        }

        let sourceFrames = data.count / MemoryLayout<Int16>.size
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(sourceFrames)) else {
            return nil
        }
        sourceBuffer.frameLength = AVAudioFrameCount(sourceFrames)
        data.withUnsafeBytes { raw in
            guard let src = raw.baseAddress,
                  let dst = sourceBuffer.int16ChannelData?[0] else { return }
            memcpy(dst, src, data.count)
        }

        let targetFrames = AVAudioFrameCount(ceil(Double(sourceFrames) * targetRate / sourceRate))
        guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetFrames) else {
            return nil
        }

        var error: NSError?
        let status = converter.convert(to: targetBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return sourceBuffer
        }
        guard status != .error, error == nil, let channelData = targetBuffer.int16ChannelData else { return nil }

        let byteCount = Int(targetBuffer.frameLength) * MemoryLayout<Int16>.size
        return Data(bytes: channelData[0], count: byteCount)
    }
}
