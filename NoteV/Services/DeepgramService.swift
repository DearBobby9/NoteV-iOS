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
    private static let streamingSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.allowsCellularAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        // Multipath handover caused socket drops on LTE-only paths in device testing.
        config.multipathServiceType = .none
        return URLSession(configuration: config)
    }()
    private let session = streamingSession
    private let transcriptContinuation: AsyncStream<TranscriptSegment>.Continuation

    private let baseURL = "wss://api.deepgram.com/v1/listen"

    /// Called when the socket dies after Metadata (LTE flap).
    private var onConnectionLost: (@Sendable (String) -> Void)?

    /// Tracks the last time audio was sent, for KeepAlive timing
    private var lastAudioSendTime: Date = Date()

    /// KeepAlive timer task
    private var keepAliveTask: Task<Void, Never>?

    /// Receive loop task
    private var receiveTask: Task<Void, Never>?

    /// Set when the receive loop exits (socket dead)
    private var receiveLoopEnded = false

    /// Whether the service is actively connected
    private(set) var isConnected: Bool = false

    /// Signal for CloseStream completion
    private var disconnectContinuation: CheckedContinuation<Void, Never>?

    /// Whether server Metadata has confirmed the connection
    private var hasReceivedMetadata = false
    private var connectionLostBeforeReady = false

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

    func setOnConnectionLost(_ handler: (@Sendable (String) -> Void)?) {
        onConnectionLost = handler
    }

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

        lastAudioSendTime = Date()
        hasReceivedMetadata = false
        connectionLostBeforeReady = false
        receiveLoopEnded = false

        NSLog("[DeepgramService] WebSocket connection initiated — model: \(NoteVConfig.Audio.deepgramModel)")

        startReceiveLoop()
        startKeepAliveTimer()
        sendTextMessage("{\"type\": \"KeepAlive\"}")

        let timeoutNs = UInt64(NoteVConfig.Audio.deepgramMetadataTimeoutSeconds * 1_000_000_000)
        let optimisticNs = UInt64(NoteVConfig.Audio.deepgramOptimisticConnectSeconds * 1_000_000_000)
        try await waitUntilReady(
            metadataTimeoutNanoseconds: timeoutNs,
            optimisticAfterNanoseconds: optimisticNs
        )

        if receiveLoopEnded, webSocketTask != nil {
            NSLog("[DeepgramService] Receive loop ended — restarting")
            receiveLoopEnded = false
            startReceiveLoop()
        }

        guard webSocketTask != nil else {
            throw DeepgramError.connectionFailed("WebSocket closed before streaming")
        }

        if !isConnected {
            isConnected = true
        }

        if hasReceivedMetadata {
            NSLog("[DeepgramService] Connection ready — Metadata received")
        } else {
            NSLog("[DeepgramService] Connection ready — optimistic streaming (LTE, no Metadata yet)")
        }
    }

    // MARK: - Send Audio

    /// Send a chunk of raw PCM audio data to Deepgram.
    /// Returns false when disconnected or send fails (caller should reconnect).
    func sendAudio(_ chunk: AudioChunk) async -> Bool {
        guard isConnected, let ws = webSocketTask else { return false }

        let message = URLSessionWebSocketTask.Message.data(chunk.data)
        do {
            try await ws.send(message)
            lastAudioSendTime = Date()
            return true
        } catch {
            NSLog("[DeepgramService] Send error: \(error.localizedDescription)")
            handleConnectionLost(reason: "send_failed: \(error.localizedDescription)")
            return false
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
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

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
                guard let self else { break }
                guard await self.webSocketTask != nil else { break }

                do {
                    let message = try await self.webSocketTask!.receive()
                    await self.handleMessage(message)
                } catch {
                    if !Task.isCancelled {
                        NSLog("[DeepgramService] Receive error: \(error.localizedDescription)")
                        await self.handleConnectionLost(reason: "receive_failed: \(error.localizedDescription)")
                    }
                    break
                }
            }

            NSLog("[DeepgramService] Receive loop ended")
            if let self {
                await self.markReceiveLoopEnded()
            }
        }
    }

    private func markReceiveLoopEnded() {
        receiveLoopEnded = true
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
                hasReceivedMetadata = true
                connectionLostBeforeReady = false
                // Unblock sendAudio as soon as Metadata arrives (connect() may still be waiting).
                isConnected = true
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
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard let self = self else { break }
                guard await self.webSocketTask != nil else { break }

                let idleTime = await Date().timeIntervalSince(self.lastAudioSendTime)
                if idleTime >= 3.5 {
                    await self.sendTextMessageChecked("{\"type\": \"KeepAlive\"}")
                    NSLog("[DeepgramService] KeepAlive sent (idle \(String(format: "%.1f", idleTime))s, connected: \(await self.isConnected))")
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
                Task { await self?.handleConnectionLost(reason: "keepalive_failed: \(error.localizedDescription)") }
            }
        }
    }

    private func handleConnectionLost(reason: String) {
        if !hasReceivedMetadata {
            connectionLostBeforeReady = true
            NSLog("[DeepgramService] Connection lost before Metadata — \(reason)")
            return
        }

        NSLog("[DeepgramService] Connection lost — \(reason)")
        isConnected = false

        keepAliveTask?.cancel()
        keepAliveTask = nil

        onConnectionLost?(reason)

        disconnectContinuation?.resume()
        disconnectContinuation = nil
    }

    private func waitUntilReady(
        metadataTimeoutNanoseconds: UInt64,
        optimisticAfterNanoseconds: UInt64
    ) async throws {
        if hasReceivedMetadata || isConnected { return }

        let pollInterval: UInt64 = 50_000_000
        var elapsed: UInt64 = 0

        while elapsed < metadataTimeoutNanoseconds {
            if hasReceivedMetadata { return }

            if elapsed >= optimisticAfterNanoseconds, webSocketTask != nil {
                isConnected = true
                NSLog("[DeepgramService] Optimistic streaming after \(NoteVConfig.Audio.deepgramOptimisticConnectSeconds)s — Metadata not received (LTE)")
                return
            }

            try await Task.sleep(nanoseconds: pollInterval)
            elapsed += pollInterval
        }

        if hasReceivedMetadata || isConnected { return }
        throw DeepgramError.connectionFailed("Timed out waiting for Deepgram connection")
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
