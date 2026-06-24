import AVFoundation
import Foundation
import UIKit

// MARK: - VisualSampleProcessor

/// Fans out CMSampleBuffers from a single visual ingress:
/// - All samples → `VideoRecorder` (full-rate MP4)
/// - Throttled subset → JPEG `TimestampedFrame` for analysis pipeline
final class VisualSampleProcessor: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.notev.visualSampleProcessor")
    private var frameContinuation: AsyncStream<TimestampedFrame>.Continuation?

    var videoRecorder: VideoRecorder?

    private var sessionStartPTS: CMTime?
    private var frameIndex = 0
    private var lastYieldTime: TimeInterval = -999
    private var samplingInterval: TimeInterval = NoteVConfig.Frame.periodicSamplingInterval

    private let ciContext = CIContext()

    lazy var frameStream: AsyncStream<TimestampedFrame> = {
        AsyncStream { continuation in
            self.frameContinuation = continuation
        }
    }()

    // MARK: - Configuration

    func setSamplingInterval(_ interval: TimeInterval) {
        queue.async { [weak self] in
            self?.samplingInterval = interval
            NSLog("[VisualSampleProcessor] Sampling interval set to \(String(format: "%.1f", interval))s")
        }
    }

    func reset() {
        queue.sync {
            sessionStartPTS = nil
            frameIndex = 0
            lastYieldTime = -999
            samplingInterval = NoteVConfig.Frame.periodicSamplingInterval
        }
    }

    func finishFrames() {
        queue.sync {
            frameContinuation?.finish()
            frameContinuation = nil
        }
    }

    /// Drains the processor queue, then waits for any in-flight recorder appends.
    func flushAndWait() async {
        let recorder = await withCheckedContinuation { (continuation: CheckedContinuation<VideoRecorder?, Never>) in
            queue.async { [weak self] in
                continuation.resume(returning: self?.videoRecorder)
            }
        }
        await recorder?.waitForPendingAppends()
    }

    // MARK: - Ingress

    func processVideoSample(_ sampleBuffer: CMSampleBuffer) {
        queue.async { [weak self] in
            self?.processVideoSampleOnQueue(sampleBuffer)
        }
    }

    /// Establishes the shared session timebase from the first media sample (video or audio).
    func establishTimebaseIfNeeded(for sampleBuffer: CMSampleBuffer) -> TimeInterval {
        queue.sync {
            establishTimebaseIfNeededOnQueue(for: sampleBuffer)
            return presentationTimeOnQueue(for: sampleBuffer) ?? 0
        }
    }

    // MARK: - Timebase (testable)

    static func sessionTimestamp(presentationTime: CMTime, sessionStart: CMTime) -> TimeInterval {
        CMTimeSubtract(presentationTime, sessionStart).seconds
    }

    // MARK: - Private

    private func processVideoSampleOnQueue(_ sampleBuffer: CMSampleBuffer) {
        videoRecorder?.appendVideo(sampleBuffer)

        guard let sessionTime = presentationTimeOnQueue(for: sampleBuffer) else { return }
        guard sessionTime - lastYieldTime >= samplingInterval else { return }
        lastYieldTime = sessionTime

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: NoteVConfig.Storage.jpegCompressionQuality) else { return }

        frameIndex += 1
        let filename = String(format: "frame_%04d.jpg", frameIndex)

        let frame = TimestampedFrame(
            timestamp: sessionTime,
            trigger: .periodic,
            changeScore: 0.0,
            imageFilename: filename,
            imageData: jpegData
        )

        frameContinuation?.yield(frame)
    }

    private func establishTimebaseIfNeededOnQueue(for sampleBuffer: CMSampleBuffer) {
        guard sessionStartPTS == nil else { return }
        sessionStartPTS = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    }

    private func presentationTimeOnQueue(for sampleBuffer: CMSampleBuffer) -> TimeInterval? {
        establishTimebaseIfNeededOnQueue(for: sampleBuffer)
        guard let sessionStartPTS else { return nil }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        return Self.sessionTimestamp(presentationTime: pts, sessionStart: sessionStartPTS)
    }
}
