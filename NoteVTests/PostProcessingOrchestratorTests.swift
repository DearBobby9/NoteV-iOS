import XCTest
@testable import NoteV

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
}
