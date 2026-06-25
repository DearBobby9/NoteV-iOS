import XCTest
@testable import NoteV

final class CaptureResilienceTests: XCTestCase {

    func testAdaptiveBaseIntervalScalesForLongSessions() {
        let short = NoteVConfig.FrameExtraction.adaptiveBaseInterval(forDuration: 1_800)
        XCTAssertEqual(short, NoteVConfig.FrameExtraction.baseSamplingInterval)

        let long = NoteVConfig.FrameExtraction.adaptiveBaseInterval(forDuration: 7_200)
        XCTAssertGreaterThan(long, NoteVConfig.FrameExtraction.baseSamplingInterval)
        XCTAssertLessThanOrEqual(long, NoteVConfig.LongSession.maxBaseSamplingInterval)
    }

    func testExtractionPlannerRespectsCandidateCapForLongSessions() {
        let longDuration: TimeInterval = 7_200
        let longInterval = NoteVConfig.FrameExtraction.adaptiveBaseInterval(forDuration: longDuration)

        let longTimestamps = ExtractionTimestampPlanner.planTimestamps(
            duration: longDuration,
            denseWindows: [],
            sceneChangeTimes: [],
            baseInterval: longInterval
        )

        XCTAssertGreaterThan(longInterval, NoteVConfig.FrameExtraction.baseSamplingInterval)
        XCTAssertLessThanOrEqual(longTimestamps.count, NoteVConfig.FrameExtraction.maxCandidateFrames)
    }

    func testSessionFilteredToTimeRangeStripsDownstreamArtifacts() {
        let session = SessionData(
            metadata: SessionMetadata(durationSeconds: 3_600),
            frames: [
                TimestampedFrame(timestamp: 100, trigger: .periodic, changeScore: 0.1, imageFilename: "a.jpg"),
                TimestampedFrame(timestamp: 2_000, trigger: .periodic, changeScore: 0.2, imageFilename: "b.jpg")
            ],
            transcriptSegments: [
                TranscriptSegment(startTime: 50, endTime: 60, text: "early", isFinal: true),
                TranscriptSegment(startTime: 1_900, endTime: 1_910, text: "late", isFinal: true)
            ],
            polishedTranscript: PolishedTranscript(segments: [], modelUsed: "test"),
            slideAnalysis: SlideAnalysisResult(uniqueSlides: [], totalFramesProcessed: 1, duplicatesRemoved: 0)
        )

        let chunk = session.filtered(to: 0..<1_800)

        XCTAssertEqual(chunk.transcriptSegments.count, 1)
        XCTAssertEqual(chunk.frames.count, 1)
        XCTAssertNil(chunk.slideAnalysis)
        XCTAssertNil(chunk.polishedTranscript)
    }

    func testCanReprocessRequiresOnDiskVideoOrContent() {
        let store = SessionStore()
        let sessionId = UUID()
        let empty = SessionData(
            metadata: SessionMetadata(sessionId: sessionId, videoFilename: NoteVConfig.Storage.sessionVideoFilename)
        )

        XCTAssertFalse(store.canReprocess(empty))

        let withTranscript = SessionData(
            metadata: SessionMetadata(sessionId: sessionId),
            transcriptSegments: [
                TranscriptSegment(startTime: 0, endTime: 1, text: "hello", isFinal: true)
            ]
        )
        XCTAssertTrue(store.canReprocess(withTranscript))
    }

    func testHasRecoverableArtifactsRequiresOnDiskVideo() {
        let session = SessionData(
            metadata: SessionMetadata(videoFilename: NoteVConfig.Storage.sessionVideoFilename)
        )

        XCTAssertFalse(session.hasRecoverableArtifacts(videoExistsOnDisk: false))
        XCTAssertTrue(session.hasRecoverableArtifacts(videoExistsOnDisk: true))
    }

    func testCheckpointMetadataNeverClaimsFinalizedVideo() {
        let checkpointMetadata = SessionMetadata(
            sessionId: UUID(),
            startDate: Date(),
            endDate: nil,
            captureSource: .phone,
            title: "Recording in progress",
            durationSeconds: 30,
            videoFilename: nil
        )
        XCTAssertNil(checkpointMetadata.videoFilename)
    }

    func testUsableVideoURLUsesDiskNotMetadata() throws {
        let store = SessionStore()
        let sessionId = UUID()
        try store.ensureSessionDirectory(for: sessionId)
        let videoURL = store.videoURL(for: sessionId)
        FileManager.default.createFile(atPath: videoURL.path, contents: Data([0x00]), attributes: nil)
        defer { try? FileManager.default.removeItem(at: store.sessionDirectory(for: sessionId)) }

        let session = SessionData(metadata: SessionMetadata(sessionId: sessionId, videoFilename: nil))
        XCTAssertNotNil(store.usableVideoURL(for: session))
        XCTAssertEqual(store.usableVideoURL(for: session)?.lastPathComponent, NoteVConfig.Storage.sessionVideoFilename)
    }

    func testUsableVideoURLReturnsNilWhenFileMissing() {
        let store = SessionStore()
        let session = SessionData(metadata: SessionMetadata(sessionId: UUID(), videoFilename: nil))
        XCTAssertNil(store.usableVideoURL(for: session))
    }

    func testCheckpointSaveClearsDerivedArtifacts() throws {
        let store = SessionStore()
        let sessionId = UUID()
        let prior = SessionData(
            metadata: SessionMetadata(sessionId: sessionId, title: "Prior"),
            polishedTranscript: PolishedTranscript(segments: [], modelUsed: "test"),
            notes: StructuredNotes(title: "Stale notes"),
            courseId: UUID(),
            courseName: "Biology 101"
        )
        try store.save(session: prior)

        let checkpoint = RecordingCheckpointBuilder.makeSessionData(
            sessionId: sessionId,
            sessionStartTime: Date().addingTimeInterval(-60),
            duration: 60,
            captureSource: .glasses,
            frames: [],
            transcriptSegments: [
                TranscriptSegment(startTime: 0, endTime: 1, text: "live", isFinal: true)
            ],
            bookmarks: [],
            existingCourse: prior
        )
        try store.save(session: checkpoint)

        let loaded = try store.load(sessionId: sessionId)
        XCTAssertNil(loaded.notes)
        XCTAssertNil(loaded.polishedTranscript)
        XCTAssertNil(loaded.slideAnalysis)
        XCTAssertEqual(loaded.transcriptSegments.count, 1)
        XCTAssertEqual(loaded.courseName, "Biology 101")
        XCTAssertNotNil(loaded.courseId)

        try? FileManager.default.removeItem(at: store.sessionDirectory(for: sessionId))
    }

    @MainActor
    func testSessionRecorderSaveRecordingCheckpointClearsDerivedArtifacts() throws {
        let store = SessionStore()
        let sessionId = UUID()
        let courseId = UUID()
        let prior = SessionData(
            metadata: SessionMetadata(sessionId: sessionId, title: "Prior"),
            polishedTranscript: PolishedTranscript(segments: [], modelUsed: "test"),
            notes: StructuredNotes(title: "Stale notes"),
            courseId: courseId,
            courseName: "Chemistry"
        )
        try store.save(session: prior)

        let recorder = SessionRecorder()
        recorder.armRecordingCheckpointState(
            sessionId: sessionId,
            transcriptSegments: [
                TranscriptSegment(startTime: 0, endTime: 1, text: "checkpoint", isFinal: true)
            ]
        )
        recorder.saveRecordingCheckpoint()

        let loaded = try store.load(sessionId: sessionId)
        XCTAssertNil(loaded.notes)
        XCTAssertNil(loaded.polishedTranscript)
        XCTAssertEqual(loaded.transcriptSegments.count, 1)
        XCTAssertEqual(loaded.courseName, "Chemistry")
        XCTAssertEqual(loaded.courseId, courseId)
        XCTAssertNil(loaded.metadata.videoFilename)

        try? FileManager.default.removeItem(at: store.sessionDirectory(for: sessionId))
    }
}
