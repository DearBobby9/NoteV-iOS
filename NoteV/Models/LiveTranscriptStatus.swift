import Foundation

// MARK: - LiveTranscriptStatus

/// Live speech-to-text connection state during recording.
enum LiveTranscriptStatus: Equatable {
    case idle
    case connecting
    case streaming
    case unavailable
}
