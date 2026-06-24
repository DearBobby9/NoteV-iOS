import XCTest
@testable import NoteV

@MainActor
final class PostProcessingOrchestratorTests: XCTestCase {

    func testPostProcessingStageDisplayNames() {
        XCTAssertEqual(PostProcessingStage.polishing.displayName, "Polishing transcript…")
        XCTAssertEqual(PostProcessingStage.extractingFrames.displayName, "Extracting frames from video…")
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

    func testFrameExtractionDisabledByDefault() {
        XCTAssertFalse(NoteVConfig.FrameExtraction.enabled)
    }
}
