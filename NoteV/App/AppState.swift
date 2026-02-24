import Foundation
import SwiftUI

// MARK: - SessionStatus

/// Current state of the recording session.
enum SessionStatus: Equatable {
    case idle
    case starting
    case recording
    case stopping
    case generatingNotes
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

// MARK: - AppState

/// Global application state, injected as an environment object.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Session

    @Published var sessionStatus: SessionStatus = .idle
    @Published var currentSession: SessionData?

    // MARK: - Capture Source

    @Published var glassesStatus: CaptureSourceStatus = .unavailable
    @Published var phoneStatus: CaptureSourceStatus = .connected
    @Published var activeCaptureSource: CaptureSource = .phone

    // MARK: - Live Session Data

    @Published var transcriptSegments: [TranscriptSegment] = []
    @Published var frameCount: Int = 0
    @Published var bookmarkCount: Int = 0
    @Published var elapsedTime: TimeInterval = 0

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
        transcriptSegments = []
        frameCount = 0
        bookmarkCount = 0
        elapsedTime = 0
        NSLog("[AppState] State reset to idle")
    }
}
