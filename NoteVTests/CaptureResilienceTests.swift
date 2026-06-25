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
}
