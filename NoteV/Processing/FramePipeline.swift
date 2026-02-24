import Foundation
import CoreImage

// MARK: - FramePipeline

/// Processes camera frames: periodic sampling + SSIM-based change detection.
/// TODO: Phase 2 — SSIM implementation and frame selection logic
final class FramePipeline {

    // MARK: - Properties

    private var frameContinuation: AsyncStream<TimestampedFrame>.Continuation?
    private var previousFrameData: Data?
    private var frameIndex: Int = 0

    lazy var significantFrameStream: AsyncStream<TimestampedFrame> = {
        AsyncStream { continuation in
            self.frameContinuation = continuation
        }
    }()

    // MARK: - Init

    init() {
        NSLog("[FramePipeline] Initialized — threshold: \(NoteVConfig.Frame.changeDetectionThreshold)")
    }

    // MARK: - Processing

    /// Start processing frames from the capture provider.
    func startProcessing(frameStream: AsyncStream<TimestampedFrame>) async {
        NSLog("[FramePipeline] startProcessing() called")
        // TODO: Phase 2
        // 1. Sample frames at periodicSamplingInterval
        // 2. Compute SSIM between consecutive frames
        // 3. If change exceeds threshold, capture burst frames
        // 4. Yield significant frames to frameContinuation
        // 5. Respect maxFramesPerSession budget
    }

    /// Stop processing.
    func stop() {
        NSLog("[FramePipeline] stop() called")
        frameContinuation?.finish()
        previousFrameData = nil
        frameIndex = 0
    }

    // MARK: - SSIM (Stub)

    /// Compute Structural Similarity Index between two image data blobs.
    /// Returns 1.0 for identical images, 0.0 for completely different.
    func computeSSIM(imageA: Data, imageB: Data) -> Double {
        // TODO: Phase 2 — Implement SSIM via CoreImage / vImage
        NSLog("[FramePipeline] computeSSIM() stub — returning 1.0 (identical)")
        return 1.0
    }
}
