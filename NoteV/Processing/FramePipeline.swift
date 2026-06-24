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

    // Burst mode: temporarily increase sampling rate after large visual change
    private var burstFramesRemaining: Int = 0
    private let burstFrameCount: Int = NoteVConfig.Frame.burstFrameCount
    private let burstSamplingInterval: TimeInterval = 1.0

    /// Callback to dynamically adjust ingress sampling interval (burst mode).
    /// Set by SessionRecorder to bridge FramePipeline → VisualSampleProcessor.
    var onSamplingIntervalChanged: ((TimeInterval) -> Void)?

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

            // Throttle removed from FramePipeline — VisualSampleProcessor pre-throttles ingress.
            // Every frame that arrives here has already passed the time gate.

            lastSampleTime = frame.timestamp

            // Compute change score against previous frame
            var changeScore = 0.0
            if let imageData = frame.imageData {
                let currentGrayscale = FrameChangeDetector.grayscale(from: imageData)
                if let previous = previousFrameGrayscale, let current = currentGrayscale {
                    changeScore = FrameChangeDetector.pixelDifference(imageA: previous, imageB: current)
                }
                previousFrameGrayscale = currentGrayscale
            }

            // Determine trigger type
            let trigger: FrameTrigger = changeScore > NoteVConfig.Frame.changeDetectionThreshold
                ? .changeDetected
                : .periodic

            // Burst mode: on significant change, speed up sampling for a few frames
            if trigger == .changeDetected && burstFramesRemaining == 0 {
                burstFramesRemaining = burstFrameCount
                onSamplingIntervalChanged?(burstSamplingInterval)
                NSLog("[FramePipeline] Burst mode ON — \(burstFrameCount) frames at \(burstSamplingInterval)s interval")
            }

            if burstFramesRemaining > 0 {
                burstFramesRemaining -= 1
                if burstFramesRemaining == 0 {
                    onSamplingIntervalChanged?(NoteVConfig.Frame.periodicSamplingInterval)
                    NSLog("[FramePipeline] Burst mode OFF — back to \(NoteVConfig.Frame.periodicSamplingInterval)s interval")
                }
            }

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

            NSLog("[FramePipeline] Frame #\(significantFrameCount) at \(String(format: "%.1f", frame.timestamp))s — trigger: \(trigger.rawValue), change: \(String(format: "%.3f", changeScore))\(burstFramesRemaining > 0 ? " [burst: \(burstFramesRemaining) left]" : "")")
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
        burstFramesRemaining = 0
    }

    // Change detection helpers live in FrameChangeDetector (shared with post-stop extraction).
}
