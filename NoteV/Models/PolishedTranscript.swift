import Foundation

// MARK: - PolishedTranscript

/// AI-polished version of the raw STT transcript.
/// Preserves the speaker's original words while cleaning up filler words,
/// fixing misrecognitions, and merging fragments into complete sentences.
struct PolishedTranscript: Identifiable, Codable, Sendable {
    let id: UUID
    let segments: [PolishedSegment]
    let polishedAt: Date
    let modelUsed: String

    init(
        id: UUID = UUID(),
        segments: [PolishedSegment],
        polishedAt: Date = Date(),
        modelUsed: String
    ) {
        self.id = id
        self.segments = segments
        self.polishedAt = polishedAt
        self.modelUsed = modelUsed
    }
}

// MARK: - PolishedSegment

/// A single cleaned-up transcript segment with optional inline images.
struct PolishedSegment: Identifiable, Codable, Sendable {
    let id: UUID
    /// Start time in seconds since session start (from original raw segment range)
    let startTime: TimeInterval
    /// End time in seconds since session start
    let endTime: TimeInterval
    /// Cleaned-up text (faithful to speaker's original words)
    let text: String
    /// Frames captured during this segment's time range
    let images: [TimelineImage]
    /// True if a bookmark was triggered during this time range
    let isBookmarked: Bool

    var duration: TimeInterval { endTime - startTime }

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        images: [TimelineImage] = [],
        isBookmarked: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.images = images
        self.isBookmarked = isBookmarked
    }
}

// MARK: - TimelineImage

/// An image displayed inline in the transcript timeline.
struct TimelineImage: Identifiable, Codable, Sendable {
    let id: UUID
    /// Filename referencing stored JPEG (e.g. "frame_001.jpg")
    let filename: String
    /// Capture time in seconds since session start
    let timestamp: TimeInterval
    /// Why this frame was captured
    let trigger: FrameTrigger

    init(
        id: UUID = UUID(),
        filename: String,
        timestamp: TimeInterval,
        trigger: FrameTrigger
    ) {
        self.id = id
        self.filename = filename
        self.timestamp = timestamp
        self.trigger = trigger
    }
}
