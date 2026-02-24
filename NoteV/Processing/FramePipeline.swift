import Foundation
import CoreImage
import UIKit

// MARK: - FramePipeline

/// Processes camera frames: periodic sampling + pixel-difference change detection.
/// Throttles to 1 frame per sampling interval, computes change scores,
/// and yields significant frames to downstream consumers.
final class FramePipeline {

    // MARK: - Properties

    private var frameContinuation: AsyncStream<TimestampedFrame>.Continuation?
    private var previousFrameGrayscale: [UInt8]?
    private var frameIndex: Int = 0
    private var significantFrameCount: Int = 0
    private var lastSampleTime: TimeInterval = -999
    private var isProcessing = false

    private let ciContext = CIContext()

    lazy var significantFrameStream: AsyncStream<TimestampedFrame> = {
        AsyncStream { continuation in
            self.frameContinuation = continuation
        }
    }()

    // MARK: - Init

    init() {
        NSLog("[FramePipeline] Initialized — threshold: \(NoteVConfig.Frame.changeDetectionThreshold), interval: \(NoteVConfig.Frame.periodicSamplingInterval)s")
    }

    // MARK: - Processing

    /// Start processing frames from the capture provider.
    func startProcessing(frameStream: AsyncStream<TimestampedFrame>) async {
        NSLog("[FramePipeline] startProcessing() called")
        isProcessing = true

        for await frame in frameStream {
            guard isProcessing else { break }

            // Budget enforcement
            if significantFrameCount >= NoteVConfig.Frame.maxFramesPerSession {
                NSLog("[FramePipeline] Max frame budget reached (\(NoteVConfig.Frame.maxFramesPerSession))")
                break
            }

            frameIndex += 1

            // Throttle: only process 1 frame per sampling interval
            let timeSinceLastSample = frame.timestamp - lastSampleTime
            guard timeSinceLastSample >= NoteVConfig.Frame.periodicSamplingInterval else {
                continue
            }

            lastSampleTime = frame.timestamp

            // Compute change score against previous frame
            var changeScore = 0.0
            if let imageData = frame.imageData {
                let currentGrayscale = downsampleToGrayscale(imageData: imageData)
                if let previous = previousFrameGrayscale, let current = currentGrayscale {
                    changeScore = computePixelDifference(imageA: previous, imageB: current)
                }
                previousFrameGrayscale = currentGrayscale
            }

            // Determine trigger type
            let trigger: FrameTrigger = changeScore > NoteVConfig.Frame.changeDetectionThreshold
                ? .changeDetected
                : .periodic

            // Create output frame with updated metadata
            let outputFrame = TimestampedFrame(
                timestamp: frame.timestamp,
                trigger: trigger,
                changeScore: changeScore,
                imageFilename: frame.imageFilename,
                imageData: frame.imageData
            )

            significantFrameCount += 1
            frameContinuation?.yield(outputFrame)

            NSLog("[FramePipeline] Frame #\(significantFrameCount) at \(String(format: "%.1f", frame.timestamp))s — trigger: \(trigger.rawValue), change: \(String(format: "%.3f", changeScore))")
        }

        NSLog("[FramePipeline] Processing loop ended — \(significantFrameCount) significant frames produced")
    }

    /// Stop processing.
    func stop() {
        NSLog("[FramePipeline] stop() called")
        isProcessing = false
        frameContinuation?.finish()
        previousFrameGrayscale = nil
        frameIndex = 0
        significantFrameCount = 0
        lastSampleTime = -999
    }

    // MARK: - Change Detection

    /// Downsample image data to 64x64 grayscale pixel array.
    private func downsampleToGrayscale(imageData: Data) -> [UInt8]? {
        guard let ciImage = CIImage(data: imageData) else { return nil }

        let targetSize = CGSize(width: 64, height: 64)

        // Scale to 64x64
        let scaleX = targetSize.width / ciImage.extent.width
        let scaleY = targetSize.height / ciImage.extent.height
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Render to pixel buffer
        let width = Int(targetSize.width)
        let height = Int(targetSize.height)
        let bytesPerRow = width * 4

        var pixelData = [UInt8](repeating: 0, count: bytesPerRow * height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Render CIImage into CGContext
        if let cgImage = ciContext.createCGImage(scaled, from: CGRect(origin: .zero, size: targetSize)) {
            context.draw(cgImage, in: CGRect(origin: .zero, size: targetSize))
        }

        // Convert RGBA to grayscale (luminance: 0.299R + 0.587G + 0.114B)
        var grayscale = [UInt8](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let r = Double(pixelData[i * 4])
            let g = Double(pixelData[i * 4 + 1])
            let b = Double(pixelData[i * 4 + 2])
            grayscale[i] = UInt8(0.299 * r + 0.587 * g + 0.114 * b)
        }

        return grayscale
    }

    /// Compute normalized L1 pixel distance between two grayscale images.
    /// Returns 0.0 for identical, 1.0 for maximally different.
    private func computePixelDifference(imageA: [UInt8], imageB: [UInt8]) -> Double {
        guard imageA.count == imageB.count, !imageA.isEmpty else { return 0.0 }

        var totalDiff: Double = 0.0
        for i in 0..<imageA.count {
            totalDiff += abs(Double(imageA[i]) - Double(imageB[i]))
        }

        // Normalize: max possible diff is 255 * pixelCount
        return totalDiff / (255.0 * Double(imageA.count))
    }
}
