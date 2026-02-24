import Foundation

// MARK: - Bookmark

/// A user-triggered bookmark capturing a moment during the session.
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

    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        frameFilename: String? = nil,
        surroundingTranscript: String = "",
        label: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.frameFilename = frameFilename
        self.surroundingTranscript = surroundingTranscript
        self.label = label
    }
}
