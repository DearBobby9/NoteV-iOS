import Foundation

// MARK: - CaptureSource

/// Which device provided capture input.
enum CaptureSource: String, Codable, Sendable {
    case glasses
    case phone
}

// MARK: - SessionMetadata

/// Metadata about a recording session.
struct SessionMetadata: Codable, Sendable {
    let sessionId: UUID
    let startDate: Date
    var endDate: Date?
    let captureSource: CaptureSource
    var title: String
    var durationSeconds: TimeInterval

    init(
        sessionId: UUID = UUID(),
        startDate: Date = Date(),
        endDate: Date? = nil,
        captureSource: CaptureSource = .phone,
        title: String = "Untitled Session",
        durationSeconds: TimeInterval = 0
    ) {
        self.sessionId = sessionId
        self.startDate = startDate
        self.endDate = endDate
        self.captureSource = captureSource
        self.title = title
        self.durationSeconds = durationSeconds
    }
}

// MARK: - SessionData

/// Complete data for a single recording session.
struct SessionData: Identifiable, Codable, Sendable {
    var id: UUID { metadata.sessionId }

    var metadata: SessionMetadata
    var frames: [TimestampedFrame]
    var transcriptSegments: [TranscriptSegment]
    var bookmarks: [Bookmark]
    var polishedTranscript: PolishedTranscript?
    var notes: StructuredNotes?
    var todos: [TodoItem]?

    init(
        metadata: SessionMetadata = SessionMetadata(),
        frames: [TimestampedFrame] = [],
        transcriptSegments: [TranscriptSegment] = [],
        bookmarks: [Bookmark] = [],
        polishedTranscript: PolishedTranscript? = nil,
        notes: StructuredNotes? = nil,
        todos: [TodoItem]? = nil
    ) {
        self.metadata = metadata
        self.frames = frames
        self.transcriptSegments = transcriptSegments
        self.bookmarks = bookmarks
        self.polishedTranscript = polishedTranscript
        self.notes = notes
        self.todos = todos
    }

    /// Full transcript as a single string
    var fullTranscript: String {
        transcriptSegments
            .filter { $0.isFinal }
            .sorted { $0.startTime < $1.startTime }
            .map { $0.text }
            .joined(separator: " ")
    }

    /// Top frames ranked by importance (bookmarks first, then highest change score)
    func topFrames(limit: Int = NoteVConfig.NoteGeneration.maxFramesInPrompt) -> [TimestampedFrame] {
        let bookmarkFrames = frames.filter { $0.trigger == .bookmark }
        let otherFrames = frames
            .filter { $0.trigger != .bookmark }
            .sorted { $0.changeScore > $1.changeScore }

        return Array((bookmarkFrames + otherFrames).prefix(limit))
    }
}
