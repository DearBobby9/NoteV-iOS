import XCTest
@testable import NoteV

private final class MockTranscriptExtractor: SessionTranscriptExtracting, @unchecked Sendable {
    let segments: [TranscriptSegment]
    private(set) var lastVideoURL: URL?

    init(segments: [TranscriptSegment]) {
        self.segments = segments
    }

    func extract(from videoURL: URL) async throws -> [TranscriptSegment] {
        lastVideoURL = videoURL
        return segments
    }
}

@MainActor
final class PostProcessingOrchestratorTests: XCTestCase {

    func testPostProcessingStageDisplayNames() {
        XCTAssertEqual(PostProcessingStage.polishing.displayName, "Polishing transcript…")
        XCTAssertEqual(PostProcessingStage.recoveringTranscript.displayName, "Recovering transcript from recording…")
        XCTAssertEqual(PostProcessingStage.extractingFrames.displayName, "Extracting frames from video…")
    }

    func testRecoveringTranscriptIsPostProcessing() {
        XCTAssertTrue(SessionStatus.recoveringTranscript.isPostProcessing)
    }

    func testSessionStatusPostProcessingFlags() {
        XCTAssertTrue(SessionStatus.polishing.isPostProcessing)
        XCTAssertTrue(SessionStatus.extractingFrames.isPostProcessing)
        XCTAssertTrue(SessionStatus.analyzingSlides.isPostProcessing)
        XCTAssertFalse(SessionStatus.complete.isPostProcessing)
        XCTAssertFalse(SessionStatus.recording.isPostProcessing)
    }

    func testSessionStatusProcessingLabels() {
        XCTAssertEqual(SessionStatus.generatingNotes.processingStageLabel, "Generating notes…")
        XCTAssertNil(SessionStatus.complete.processingStageLabel)
    }

    func testSessionVideoFilenameMatchesStorageConfig() {
        XCTAssertEqual(NoteVConfig.Storage.sessionVideoFilename, "session.mp4")
    }

    func testProcessEmptySessionFailsAtFinalizing() async {
        let orchestrator = PostProcessingOrchestrator()
        let appState = AppState()
        let session = SessionData(metadata: SessionMetadata())

        let result = await orchestrator.process(session: session, appState: appState)

        XCTAssertEqual(result.failedStage, .finalizing)
        XCTAssertTrue(result.warnings.contains { $0.contains("no video") })
        if case .error(let message) = appState.sessionStatus {
            XCTAssertTrue(message.contains("no video"))
        } else {
            XCTFail("Expected error status, got \(appState.sessionStatus)")
        }
    }

    func testRecoveringTranscriptUsesDiskVideoWhenFilenameNil() async throws {
        let store = SessionStore()
        let sessionId = UUID()
        try store.ensureSessionDirectory(for: sessionId)
        let videoURL = store.videoURL(for: sessionId)
        FileManager.default.createFile(atPath: videoURL.path, contents: Data([0x00, 0x01]), attributes: nil)
        defer { try? FileManager.default.removeItem(at: store.sessionDirectory(for: sessionId)) }

        let recovered = [
            TranscriptSegment(startTime: 0, endTime: 2, text: "Recovered from MP4", isFinal: true)
        ]
        let mockExtractor = MockTranscriptExtractor(segments: recovered)
        let orchestrator = PostProcessingOrchestrator(transcriptExtractor: mockExtractor)
        let appState = AppState()

        let session = SessionData(
            metadata: SessionMetadata(sessionId: sessionId, videoFilename: nil),
            frames: [
                TimestampedFrame(timestamp: 0, trigger: .periodic, changeScore: 0.1, imageFilename: "frame.jpg")
            ],
            transcriptSegments: []
        )
        appState.currentSession = session

        let result = await orchestrator.process(
            session: session,
            appState: appState,
            fromStage: .recoveringTranscript
        )

        XCTAssertEqual(result.session.transcriptSegments.count, 1)
        XCTAssertEqual(result.session.transcriptSegments.first?.text, "Recovered from MP4")
        XCTAssertEqual(mockExtractor.lastVideoURL, videoURL)
    }
}
