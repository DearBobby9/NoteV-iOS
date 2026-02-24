import Foundation
@preconcurrency import AVFoundation

// MARK: - PhoneCaptureProvider

/// Captures frames and audio from the iPhone's camera and microphone.
/// Used for development without glasses and as a demo fallback.
/// TODO: Phase 1 — Full AVCaptureSession implementation
final class PhoneCaptureProvider: NSObject, CaptureProvider {

    // MARK: - Properties

    private let captureSession = AVCaptureSession()
    private var frameContinuation: AsyncStream<TimestampedFrame>.Continuation?
    private var audioContinuation: AsyncStream<AudioChunk>.Continuation?

    private(set) var isAvailable: Bool = true

    lazy var frameStream: AsyncStream<TimestampedFrame> = {
        AsyncStream { continuation in
            self.frameContinuation = continuation
        }
    }()

    lazy var audioStream: AsyncStream<AudioChunk> = {
        AsyncStream { continuation in
            self.audioContinuation = continuation
        }
    }()

    // MARK: - Init

    override init() {
        super.init()
        NSLog("[PhoneCaptureProvider] Initialized — iPhone camera fallback mode")
        // TODO: Phase 1 — Configure AVCaptureSession
        // 1. Add back camera video input
        // 2. Add microphone audio input
        // 3. Add video data output (for frame sampling)
        // 4. Add audio data output (for PCM chunks)
    }

    // MARK: - CaptureProvider

    func startCapture() async throws {
        NSLog("[PhoneCaptureProvider] startCapture() called")
        // TODO: Phase 1 — Start AVCaptureSession on background queue
        // captureSession.startRunning()
    }

    func stopCapture() async {
        NSLog("[PhoneCaptureProvider] stopCapture() called")
        // TODO: Phase 1 — Stop AVCaptureSession
        // captureSession.stopRunning()
        frameContinuation?.finish()
        audioContinuation?.finish()
    }

    func capturePhoto() async throws -> Data {
        NSLog("[PhoneCaptureProvider] capturePhoto() called")
        // TODO: Phase 1 — Capture high-res still from AVCapturePhotoOutput
        return Data()
    }
}
