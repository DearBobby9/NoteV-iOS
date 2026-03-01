import Foundation
import SwiftUI

// MARK: - SessionStatus

/// Current state of the recording session.
enum SessionStatus: Equatable {
    case idle
    case starting
    case recording
    case stopping
    case polishing          // Transcript polishing in progress
    case generatingNotes
    case extractingTodos    // TODO extraction in progress
    case analyzingSlides    // Slide analysis in progress
    case complete
    case error(String)
}

// MARK: - CaptureSourceStatus

/// Status of a capture source (glasses or phone).
enum CaptureSourceStatus: Equatable {
    case unavailable
    case disconnected
    case connecting
    case connected
    case active
}

// MARK: - NavigationDestination

/// Navigation destinations for the main flow.
enum NavigationDestination: Hashable {
    case liveSession
    case notesResult
    case sessionResult
    case pastSessionResult
    case sessionList
}

// MARK: - AppState

/// Global application state, injected as an environment object.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Navigation

    @Published var navigationPath = NavigationPath()

    // MARK: - Session

    @Published var sessionStatus: SessionStatus = .idle
    @Published var currentSession: SessionData?
    @Published var generatedNotes: StructuredNotes?

    // MARK: - Capture Source

    @Published var glassesStatus: CaptureSourceStatus = .unavailable
    @Published var phoneStatus: CaptureSourceStatus = .connected
    @Published var activeCaptureSource: CaptureSource = .phone

    // MARK: - Live Session Data

    @Published var transcriptSegments: [TranscriptSegment] = []
    @Published var frameCount: Int = 0
    @Published var bookmarkCount: Int = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var latestFrameData: Data?
    @Published var bookmarkTimestamps: [TimeInterval] = []
    @Published var extractedTodos: [TodoItem] = []
    @Published var autoBookmarkCount: Int = 0
    @Published var latestAutoBookmarkPhrase: String?

    // MARK: - Past Sessions

    @Published var pastSessions: [SessionData] = []

    // MARK: - Computed

    var isRecording: Bool {
        sessionStatus == .recording
    }

    var isGlassesAvailable: Bool {
        glassesStatus == .connected || glassesStatus == .active
    }

    var latestTranscript: String {
        transcriptSegments.last?.text ?? ""
    }

    var formattedElapsedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Actions

    func reset() {
        sessionStatus = .idle
        currentSession = nil
        generatedNotes = nil
        transcriptSegments = []
        frameCount = 0
        bookmarkCount = 0
        elapsedTime = 0
        latestFrameData = nil
        bookmarkTimestamps = []
        extractedTodos = []
        autoBookmarkCount = 0
        latestAutoBookmarkPhrase = nil
        NSLog("[AppState] State reset to idle")
    }
}
