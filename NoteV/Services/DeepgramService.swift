import Foundation

// MARK: - DeepgramError

enum DeepgramError: LocalizedError {
    case notConfigured
    case invalidURL
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Deepgram API key not configured"
        case .invalidURL: return "Invalid Deepgram WebSocket URL"
        case .connectionFailed(let msg): return "Deepgram connection failed: \(msg)"
        }
    }
}

// MARK: - Deepgram Response Models (private)

private struct DeepgramResponse: Decodable {
    let type: String
    let start: Double?
    let duration: Double?
    let is_final: Bool?
    let speech_final: Bool?
    let channel: DeepgramChannel?
    let from_finalize: Bool?
}

private struct DeepgramChannel: Decodable {
    let alternatives: [DeepgramAlternative]
}

private struct DeepgramAlternative: Decodable {
    let transcript: String
    let confidence: Double
}

// MARK: - DeepgramService

/// Streaming speech-to-text via Deepgram's WebSocket API.
/// Uses native URLSessionWebSocketTask (no third-party dependencies).
///
/// Actor isolation serializes all property access, eliminating race conditions
/// on isConnected, webSocketTask, continuations, and timer state.
///
/// Protocol:
/// - Client sends raw PCM audio as binary WebSocket frames
/// - Client sends KeepAlive JSON every ~5s when idle (prevents 10s timeout)
/// - Client sends Finalize to flush buffered audio
/// - Client sends CloseStream for graceful disconnect
/// - Server responds with Results JSON containing transcript segments
actor DeepgramService {

    // MARK: - Properties

    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private let transcriptContinuation: AsyncStream<TranscriptSegment>.Continuation

    private let baseURL = "wss://api.deepgram.com/v1/listen"

    /// Tracks the last time audio was sent, for KeepAlive timing
    private var lastAudioSendTime: Date = Date()

    /// KeepAlive timer task
    private var keepAliveTask: Task<Void, Never>?

    /// Receive loop task
    private var receiveTask: Task<Void, Never>?

    /// Whether the service is actively connected
    private(set) var isConnected: Bool = false

    /// Signal for CloseStream completion
    private var disconnectContinuation: CheckedContinuation<Void, Never>?

    /// Eagerly initialized transcript stream (thread-safe, no lazy var hazard)
    nonisolated let transcriptStream: AsyncStream<TranscriptSegment>

    // MARK: - Init

    init() {
        let (stream, continuation) = AsyncStream<TranscriptSegment>.makeStream()
        self.transcriptStream = stream
        self.transcriptContinuation = continuation
        NSLog("[DeepgramService] Initialized — model: \(NoteVConfig.Audio.deepgramModel)")
    }

    // MARK: - Connection

    /// Connect to Deepgram WebSocket for streaming STT.
    func connect() async throws {
        NSLog("[DeepgramService] connect() called")

        guard APIKeys.isDeepgramConfigured else {
            throw DeepgramError.notConfigured
        }

        let queryParams = [
            "model=\(NoteVConfig.Audio.deepgramModel)",
            "sample_rate=\(NoteVConfig.Audio.sampleRate)",
            "channels=\(NoteVConfig.Audio.channels)",
            "encoding=linear16",
            "language=en",
            "punctuate=true",
            "smart_format=true",
            "interim_results=true",
            "endpointing=300"
        ].joined(separator: "&")

        let urlString = "\(baseURL)?\(queryParams)"
        guard let url = URL(string: urlString) else {
            throw DeepgramError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(APIKeys.deepgramAPIKey)", forHTTPHeaderField: "Authorization")

        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        isConnected = true
        lastAudioSendTime = Date()

        NSLog("[DeepgramService] WebSocket connection initiated — model: \(NoteVConfig.Audio.deepgramModel)")

        startReceiveLoop()
        startKeepAliveTimer()
    }

    // MARK: - Send Audio

    /// Send a chunk of raw PCM audio data to Deepgram.
    /// Async to apply natural backpressure if the WebSocket can't keep up.
    func sendAudio(_ chunk: AudioChunk) async {
        guard isConnected, let ws = webSocketTask else { return }

        let message = URLSessionWebSocketTask.Message.data(chunk.data)
        do {
            try await ws.send(message)
            lastAudioSendTime = Date()
        } catch {
            NSLog("[DeepgramService] Send error: \(error.localizedDescription)")
            handleConnectionLost()
        }
    }

    // MARK: - Control Messages

    /// Send Finalize to force-process any buffered audio. Connection stays open.
    func sendFinalize() {
        NSLog("[DeepgramService] Sending Finalize")
        sendTextMessage("{\"type\": \"Finalize\"}")
    }

    /// Send CloseStream for graceful disconnect. Server finishes processing then closes.
    func sendCloseStream() async {
        NSLog("[DeepgramService] Sending CloseStream")
        sendTextMessage("{\"type\": \"CloseStream\"}")

        // Wait for server to close connection (with 3s timeout)
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                await self?.waitForDisconnectSignal()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
            _ = await group.next()
            group.cancelAll()
        }

        // Brief drain period to let receive loop process any final messages
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        NSLog("[DeepgramService] CloseStream acknowledged or timed out")
    }

    // MARK: - Disconnect

    /// Force-close the WebSocket connection immediately.
    func disconnect() {
        NSLog("[DeepgramService] disconnect() called")

        keepAliveTask?.cancel()
        keepAliveTask = nil

        receiveTask?.cancel()
        receiveTask = nil

        isConnected = false

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        transcriptContinuation.finish()

        // Signal anyone waiting for disconnect
        disconnectContinuation?.resume()
        disconnectContinuation = nil
    }

    // MARK: - Receive Loop

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                guard await self.isConnected else { break }
                guard let ws = await self.webSocketTask else { break }

                do {
                    let message = try await ws.receive()
                    await self.handleMessage(message)
                } catch {
                    if !Task.isCancelled {
                        let connected = await self.isConnected
                        if connected {
                            NSLog("[DeepgramService] Receive error: \(error.localizedDescription)")
                            await self.handleConnectionLost()
                        }
                    }
                    break
                }
            }

            NSLog("[DeepgramService] Receive loop ended")
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseTextMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseTextMessage(text)
            }
        @unknown default:
            NSLog("[DeepgramService] Unknown message type received")
        }
    }

    // MARK: - JSON Parsing

    private func parseTextMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            NSLog("[DeepgramService] ERROR: Could not encode message to data")
            return
        }

        do {
            let response = try JSONDecoder().decode(DeepgramResponse.self, from: data)

            switch response.type {
            case "Results":
                handleResultsMessage(response)
            case "Metadata":
                NSLog("[DeepgramService] Metadata received — connection confirmed")
            case "UtteranceEnd":
                NSLog("[DeepgramService] UtteranceEnd received")
            case "SpeechStarted":
                NSLog("[DeepgramService] SpeechStarted received")
            default:
                NSLog("[DeepgramService] Unknown message type: \(response.type)")
            }
        } catch {
            NSLog("[DeepgramService] JSON parse error: \(error.localizedDescription) — raw: \(text.prefix(200))")
        }
    }

    private func handleResultsMessage(_ response: DeepgramResponse) {
        guard let channel = response.channel,
              let best = channel.alternatives.first else {
            return
        }

        let transcript = best.transcript.trimmingCharacters(in: .whitespaces)

        // Skip empty transcripts (Deepgram sends empty Results for silence)
        guard !transcript.isEmpty else { return }

        let start = response.start ?? 0
        let duration = response.duration ?? 0
        let isFinal = response.is_final ?? false
        let speechFinal = response.speech_final ?? false
        let fromFinalize = response.from_finalize ?? false

        let segment = TranscriptSegment(
            startTime: start,
            endTime: start + duration,
            text: transcript,
            isFinal: isFinal
        )

        transcriptContinuation.yield(segment)

        NSLog("[DeepgramService] Segment: \"\(transcript.prefix(80))\" (final: \(isFinal), speechFinal: \(speechFinal), fromFinalize: \(fromFinalize), conf: \(String(format: "%.2f", best.confidence)), time: \(String(format: "%.1f-%.1f", start, start + duration))s)")
    }

    // MARK: - KeepAlive Timer

    private func startKeepAliveTimer() {
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                guard let self = self else { break }
                guard await self.isConnected else { break }

                let idleTime = await Date().timeIntervalSince(self.lastAudioSendTime)
                if idleTime >= 4.0 {
                    await self.sendTextMessageChecked("{\"type\": \"KeepAlive\"}")
                    NSLog("[DeepgramService] KeepAlive sent (idle \(String(format: "%.1f", idleTime))s)")
                }
            }
        }
    }

    // MARK: - Helpers

    /// Fire-and-forget text send (for Finalize, CloseStream — errors are non-critical)
    private func sendTextMessage(_ text: String) {
        guard let ws = webSocketTask else { return }
        let message = URLSessionWebSocketTask.Message.string(text)
        ws.send(message) { error in
            if let error = error {
                NSLog("[DeepgramService] Text send error: \(error.localizedDescription)")
            }
        }
    }

    /// Checked text send — triggers connection lost on failure (for KeepAlive)
    private func sendTextMessageChecked(_ text: String) {
        guard let ws = webSocketTask else { return }
        let message = URLSessionWebSocketTask.Message.string(text)
        ws.send(message) { [weak self] error in
            if let error = error {
                NSLog("[DeepgramService] Text send error: \(error.localizedDescription)")
                Task { await self?.handleConnectionLost() }
            }
        }
    }

    private func handleConnectionLost() {
        guard isConnected else { return } // Idempotent
        NSLog("[DeepgramService] Connection lost")
        isConnected = false

        keepAliveTask?.cancel()
        keepAliveTask = nil

        // Signal anyone waiting for disconnect
        disconnectContinuation?.resume()
        disconnectContinuation = nil

        // Don't finish transcriptContinuation here — AudioPipeline controls that lifecycle
    }

    private func waitForDisconnectSignal() async {
        // Actor isolation serializes access — no TOCTOU race possible
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if !isConnected {
                continuation.resume()
            } else {
                disconnectContinuation = continuation
            }
        }
    }
}
