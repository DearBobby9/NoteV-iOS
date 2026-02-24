import Foundation

// MARK: - CaptureProvider

/// Protocol for audio + visual capture from glasses or phone.
/// Two implementations: GlassesCaptureProvider (DAT SDK) and PhoneCaptureProvider (AVCaptureSession).
protocol CaptureProvider: AnyObject {
    /// Whether this capture source is currently available
    var isAvailable: Bool { get }

    /// Start capturing audio and video frames
    func startCapture() async throws

    /// Stop all capture streams
    func stopCapture() async

    /// Capture a single high-resolution photo (used for bookmarks)
    func capturePhoto() async throws -> Data

    /// Async stream of timestamped video frames
    var frameStream: AsyncStream<TimestampedFrame> { get }

    /// Async stream of raw audio chunks
    var audioStream: AsyncStream<AudioChunk> { get }
}
