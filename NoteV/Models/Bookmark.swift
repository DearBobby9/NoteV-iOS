import Foundation

// MARK: - BookmarkSource

/// Whether a bookmark was created manually or auto-detected.
enum BookmarkSource: String, Codable, Sendable {
    case manual
    case auto
}

// MARK: - Bookmark

/// A user-triggered or auto-detected bookmark capturing a moment during the session.
struct Bookmark: Identifiable, Codable, Sendable {
    let id: UUID
    /// Seconds since session start when bookmark was triggered
    let timestamp: TimeInterval
    /// High-res frame captured at bookmark time (filename reference)
    let frameFilename: String?
    /// Transcript text surrounding the bookmark moment
    let surroundingTranscript: String
    /// Optional user-provided label
    var label: String?
    /// Manual or auto-detected
    var source: BookmarkSource
    /// Confidence score for auto-detected bookmarks (0.0-1.0)
    var confidence: Double?
    /// Phrase that triggered the auto-detection
    var triggerPhrase: String?
    /// Detection tier (1-4) for auto bookmarks
    var detectionTier: Int?

    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        frameFilename: String? = nil,
        surroundingTranscript: String = "",
        label: String? = nil,
        source: BookmarkSource = .manual,
        confidence: Double? = nil,
        triggerPhrase: String? = nil,
        detectionTier: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.frameFilename = frameFilename
        self.surroundingTranscript = surroundingTranscript
        self.label = label
        self.source = source
        self.confidence = confidence
        self.triggerPhrase = triggerPhrase
        self.detectionTier = detectionTier
    }
}
