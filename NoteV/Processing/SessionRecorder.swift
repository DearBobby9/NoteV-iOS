import Foundation

// MARK: - SessionRecorder

/// Orchestrates all pipelines during a recording session.
/// Ties together CaptureManager, AudioPipeline, FramePipeline, and BookmarkDetector.
/// Assembles the final SessionData when recording ends.
/// TODO: Phase 2 — Full orchestration logic
@MainActor
final class SessionRecorder: ObservableObject {

    // MARK: - Properties

    private let captureManager: CaptureManager
    private let audioPipeline: AudioPipeline
    private let framePipeline: FramePipeline
    private let bookmarkDetector: BookmarkDetector

    @Published private(set) var isRecording = false
    private var sessionStartTime: Date?
    private var collectedFrames: [TimestampedFrame] = []
    private var collectedSegments: [TranscriptSegment] = []
    private var collectedBookmarks: [Bookmark] = []

    // MARK: - Init

    init() {
        self.captureManager = CaptureManager()
        self.audioPipeline = AudioPipeline()
        self.framePipeline = FramePipeline()
        self.bookmarkDetector = BookmarkDetector()
        NSLog("[SessionRecorder] Initialized")
    }

    // MARK: - Recording Lifecycle

    /// Start a new recording session.
    func startRecording() async throws {
        NSLog("[SessionRecorder] startRecording() called")
        // TODO: Phase 2
        // 1. Start CaptureManager
        // 2. Feed audio stream to AudioPipeline
        // 3. Feed frame stream to FramePipeline
        // 4. Start BookmarkDetector
        // 5. Collect results from all pipelines
        isRecording = true
        sessionStartTime = Date()
    }

    /// Stop recording and assemble SessionData.
    func stopRecording() async -> SessionData {
        NSLog("[SessionRecorder] stopRecording() called")
        isRecording = false

        // TODO: Phase 2 — Stop all pipelines, collect final data
        await captureManager.stopCapture()
        audioPipeline.stop()
        framePipeline.stop()
        bookmarkDetector.stop()

        let metadata = SessionMetadata(
            startDate: sessionStartTime ?? Date(),
            endDate: Date(),
            captureSource: captureManager.activeSource,
            durationSeconds: Date().timeIntervalSince(sessionStartTime ?? Date())
        )

        let session = SessionData(
            metadata: metadata,
            frames: collectedFrames,
            transcriptSegments: collectedSegments,
            bookmarks: collectedBookmarks
        )

        NSLog("[SessionRecorder] Session assembled — \(collectedFrames.count) frames, \(collectedSegments.count) segments, \(collectedBookmarks.count) bookmarks")

        // Reset
        collectedFrames = []
        collectedSegments = []
        collectedBookmarks = []
        sessionStartTime = nil

        return session
    }
}
