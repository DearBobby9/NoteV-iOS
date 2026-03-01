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
    var slideAnalysis: SlideAnalysisResult?
    var courseId: UUID?
    var courseName: String?

    init(
        metadata: SessionMetadata = SessionMetadata(),
        frames: [TimestampedFrame] = [],
        transcriptSegments: [TranscriptSegment] = [],
        bookmarks: [Bookmark] = [],
        polishedTranscript: PolishedTranscript? = nil,
        notes: StructuredNotes? = nil,
        todos: [TodoItem]? = nil,
        slideAnalysis: SlideAnalysisResult? = nil,
        courseId: UUID? = nil,
        courseName: String? = nil
    ) {
        self.metadata = metadata
        self.frames = frames
        self.transcriptSegments = transcriptSegments
        self.bookmarks = bookmarks
        self.polishedTranscript = polishedTranscript
        self.notes = notes
        self.todos = todos
        self.slideAnalysis = slideAnalysis
        self.courseId = courseId
        self.courseName = courseName
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
        let bookmarkFrames = frames.filter { $0.trigger == .bookmark || $0.trigger == .smartBookmark }
        let otherFrames = frames
            .filter { $0.trigger != .bookmark && $0.trigger != .smartBookmark }
            .sorted { $0.changeScore > $1.changeScore }

        return Array((bookmarkFrames + otherFrames).prefix(limit))
    }
}

// MARK: - SlideAnalysisResult

struct SlideAnalysisResult: Codable, Sendable {
    let uniqueSlides: [UniqueSlide]
    let totalFramesProcessed: Int
    let duplicatesRemoved: Int
}

// MARK: - UniqueSlide

struct UniqueSlide: Codable, Sendable {
    let representativeFrame: String
    let timestamp: TimeInterval
    let slideNumber: Int
    let extractedText: String?
    let duplicateCount: Int
}
