import Foundation

// MARK: - FrameTrigger

/// Why a frame was captured.
enum FrameTrigger: String, Codable, Sendable {
    /// Captured on a regular interval (e.g. every 5 seconds)
    case periodic
    /// SSIM change detection exceeded threshold
    case changeDetected
    /// User-triggered bookmark
    case bookmark
}

// MARK: - TimestampedFrame

/// A single captured image with metadata.
struct TimestampedFrame: Identifiable, Codable, Sendable {
    let id: UUID
    /// Seconds since session start
    let timestamp: TimeInterval
    /// Why this frame was captured
    let trigger: FrameTrigger
    /// SSIM change score relative to previous frame (0.0 = identical, 1.0 = completely different)
    let changeScore: Double
    /// Filename for the stored JPEG (e.g. "frame_001.jpg")
    let imageFilename: String

    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        trigger: FrameTrigger = .periodic,
        changeScore: Double = 0.0,
        imageFilename: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.trigger = trigger
        self.changeScore = changeScore
        self.imageFilename = imageFilename
    }
}
