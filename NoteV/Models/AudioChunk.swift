import Foundation

// MARK: - AudioChunk

/// A chunk of raw PCM audio data with timing information.
struct AudioChunk: Identifiable, Codable, Sendable {
    let id: UUID
    /// Seconds since session start
    let timestamp: TimeInterval
    /// Raw PCM audio bytes
    let data: Data
    /// Duration of this chunk in seconds
    let duration: TimeInterval

    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        data: Data,
        duration: TimeInterval
    ) {
        self.id = id
        self.timestamp = timestamp
        self.data = data
        self.duration = duration
    }
}
