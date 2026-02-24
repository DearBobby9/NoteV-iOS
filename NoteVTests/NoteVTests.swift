import XCTest
@testable import NoteV

final class NoteVTests: XCTestCase {

    // MARK: - SessionData Codable Round-Trip

    func testSessionDataCodableRoundTrip() throws {
        let frame = TimestampedFrame(
            timestamp: 10.5,
            trigger: .periodic,
            changeScore: 0.3,
            imageFilename: "frame_001.jpg"
        )

        let segment = TranscriptSegment(
            startTime: 5.0,
            endTime: 10.0,
            text: "Hello, this is a test transcript.",
            isFinal: true
        )

        let bookmark = Bookmark(
            timestamp: 8.0,
            frameFilename: "bookmark_001.jpg",
            surroundingTranscript: "test transcript context"
        )

        let metadata = SessionMetadata(
            captureSource: .phone,
            title: "Test Session"
        )

        let session = SessionData(
            metadata: metadata,
            frames: [frame],
            transcriptSegments: [segment],
            bookmarks: [bookmark]
        )

        // Encode
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        XCTAssertFalse(data.isEmpty, "Encoded data should not be empty")

        // Decode
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SessionData.self, from: data)

        // Verify
        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.metadata.title, "Test Session")
        XCTAssertEqual(decoded.metadata.captureSource, .phone)
        XCTAssertEqual(decoded.frames.count, 1)
        XCTAssertEqual(decoded.frames.first?.trigger, .periodic)
        XCTAssertEqual(decoded.frames.first?.changeScore, 0.3, accuracy: 0.001)
        XCTAssertEqual(decoded.transcriptSegments.count, 1)
        XCTAssertEqual(decoded.transcriptSegments.first?.text, "Hello, this is a test transcript.")
        XCTAssertEqual(decoded.bookmarks.count, 1)
        XCTAssertEqual(decoded.bookmarks.first?.surroundingTranscript, "test transcript context")
    }

    // MARK: - StructuredNotes Codable

    func testStructuredNotesCodableRoundTrip() throws {
        let image = NoteImage(filename: "img_001.jpg", caption: "A diagram", timestamp: 15.0)
        let section = NoteSection(title: "Introduction", content: "Some content", images: [image], order: 0)
        let notes = StructuredNotes(
            title: "Test Notes",
            summary: "A test summary",
            sections: [section],
            keyTakeaways: ["Takeaway 1", "Takeaway 2"]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(notes)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StructuredNotes.self, from: data)

        XCTAssertEqual(decoded.title, "Test Notes")
        XCTAssertEqual(decoded.sections.count, 1)
        XCTAssertEqual(decoded.sections.first?.images.count, 1)
        XCTAssertEqual(decoded.keyTakeaways.count, 2)
    }

    // MARK: - BookmarkDetector Keyword Check

    func testBookmarkKeywordDetection() {
        let detector = BookmarkDetector()
        XCTAssertTrue(detector.containsKeyword("Please mark this section"))
        XCTAssertTrue(detector.containsKeyword("MARK"))
        XCTAssertFalse(detector.containsKeyword("This is a regular sentence"))
    }

    // MARK: - NoteVConfig Values

    func testConfigDefaults() {
        XCTAssertEqual(NoteVConfig.Frame.periodicSamplingInterval, 5.0)
        XCTAssertEqual(NoteVConfig.Frame.changeDetectionThreshold, 0.15)
        XCTAssertEqual(NoteVConfig.Audio.sampleRate, 16_000)
        XCTAssertEqual(NoteVConfig.Bookmark.keyword, "mark")
        XCTAssertEqual(NoteVConfig.NoteGeneration.maxFramesInPrompt, 20)
    }
}
