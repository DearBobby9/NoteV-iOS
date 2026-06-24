import Foundation

// MARK: - CaptureProvider

/// Protocol for audio + visual capture from glasses or phone.
/// Two implementations: GlassesCaptureProvider (DAT SDK) and PhoneCaptureProvider (AVCaptureSession).
@MainActor
protocol CaptureProvider: AnyObject {
    /// Whether this capture source is currently available
    var isAvailable: Bool { get }

    /// When set before `startCapture()`, full-session MP4 is written alongside frame snapshots.
    var videoRecorder: VideoRecorder? { get set }

    /// When set before `startCapture()`, video samples fan out to MP4 + throttled frames.
    var visualSampleProcessor: VisualSampleProcessor? { get set }

    /// Start capturing audio and video frames
    func startCapture() async throws

    /// Stop all capture streams
    func stopCapture() async

    /// Drain in-flight sample buffers before finalizing the session MP4.
    func flushPendingSamples() async

    /// Capture a single high-resolution photo (used for bookmarks)
    func capturePhoto() async throws -> Data

    /// Async stream of timestamped video frames
    var frameStream: AsyncStream<TimestampedFrame> { get }

    /// Async stream of raw audio chunks
    var audioStream: AsyncStream<AudioChunk> { get }
}
