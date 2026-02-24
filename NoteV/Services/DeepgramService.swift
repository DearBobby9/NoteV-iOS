import Foundation

// MARK: - DeepgramService

/// Streaming speech-to-text via Deepgram's WebSocket API.
/// Uses native URLSessionWebSocketTask (no Starscream dependency).
/// TODO: Phase 2 — Full WebSocket implementation
final class DeepgramService {

    // MARK: - Properties

    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var transcriptContinuation: AsyncStream<TranscriptSegment>.Continuation?

    private let baseURL = "wss://api.deepgram.com/v1/listen"

    lazy var transcriptStream: AsyncStream<TranscriptSegment> = {
        AsyncStream { continuation in
            self.transcriptContinuation = continuation
        }
    }()

    // MARK: - Init

    init() {
        NSLog("[DeepgramService] Initialized — model: \(NoteVConfig.Audio.deepgramModel)")
    }

    // MARK: - Connection

    /// Connect to Deepgram WebSocket for streaming STT.
    func connect() async throws {
        NSLog("[DeepgramService] connect() called")

        guard APIKeys.isDeepgramConfigured else {
            NSLog("[DeepgramService] ERROR: Deepgram API key not configured")
            return
        }

        // TODO: Phase 2
        // 1. Build WebSocket URL with query params (model, sample_rate, channels, etc.)
        // 2. Create URLSessionWebSocketTask with auth header
        // 3. Start receiving messages in a loop
        // 4. Parse JSON responses into TranscriptSegments

        let queryParams = [
            "model=\(NoteVConfig.Audio.deepgramModel)",
            "sample_rate=\(NoteVConfig.Audio.sampleRate)",
            "channels=\(NoteVConfig.Audio.channels)",
            "encoding=linear16",
            "punctuate=true",
            "interim_results=true"
        ].joined(separator: "&")

        let urlString = "\(baseURL)?\(queryParams)"
        guard let url = URL(string: urlString) else {
            NSLog("[DeepgramService] ERROR: Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(APIKeys.deepgramAPIKey)", forHTTPHeaderField: "Authorization")

        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        NSLog("[DeepgramService] WebSocket connection initiated")
    }

    // MARK: - Send Audio

    /// Send a chunk of audio data to Deepgram.
    func sendAudio(_ chunk: AudioChunk) {
        // TODO: Phase 2 — Send binary PCM data via WebSocket
        let message = URLSessionWebSocketTask.Message.data(chunk.data)
        webSocketTask?.send(message) { error in
            if let error = error {
                NSLog("[DeepgramService] Send error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Disconnect

    /// Close the WebSocket connection.
    func disconnect() {
        NSLog("[DeepgramService] disconnect() called")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        transcriptContinuation?.finish()
    }
}
