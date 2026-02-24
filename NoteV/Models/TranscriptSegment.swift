import Foundation

// MARK: - TranscriptSegment

/// A segment of transcribed speech.
struct TranscriptSegment: Identifiable, Codable, Sendable {
    let id: UUID
    /// Start time in seconds since session start
    let startTime: TimeInterval
    /// End time in seconds since session start
    let endTime: TimeInterval
    /// Transcribed text content
    var text: String
    /// Whether this is a finalized transcript (vs. interim/partial)
    var isFinal: Bool

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        isFinal: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.isFinal = isFinal
    }

    /// Duration of this segment in seconds
    var duration: TimeInterval {
        endTime - startTime
    }
}
