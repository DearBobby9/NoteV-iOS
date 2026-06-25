import AVFoundation
import Foundation

// MARK: - AudioSampleBufferFactory

/// Builds CMSampleBuffers from raw PCM for MP4 muxing (glasses mic path).
enum AudioSampleBufferFactory {

    static func makePCMSampleBuffer(
        data: Data,
        sampleRate: Double,
        channels: UInt32,
        presentationTime: CMTime
    ) -> CMSampleBuffer? {
        let bytesPerFrame = Int(channels) * MemoryLayout<Int16>.size
        guard bytesPerFrame > 0, data.count >= bytesPerFrame else { return nil }

        let frameCount = data.count / bytesPerFrame

        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        ) == noErr,
              let blockBuffer else {
            return nil
        }

        data.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.baseAddress else { return }
            CMBlockBufferReplaceDataBytes(
                with: source,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: data.count
            )
        }

        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(bytesPerFrame),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(bytesPerFrame),
            mChannelsPerFrame: channels,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var formatDescription: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        ) == noErr,
              let formatDescription else {
            return nil
        }

        var sampleBuffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )

        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr else {
            return nil
        }

        return sampleBuffer
    }
}
