import Foundation
import AVFoundation

// MARK: - DeepgramVoiceService

/// Lightweight Deepgram WebSocket client for chat voice input.
/// Unlike DeepgramService (used for recording), this is optimized for short-form dictation:
/// - Shorter endpointing (200ms) for responsive results
/// - UtteranceEnd detection (1.5s silence = auto-stop)
/// - Returns concatenated final transcript
/// - No KeepAlive (short-lived connections)
actor DeepgramVoiceService {

    // MARK: - Properties

    private var webSocketTask: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private var audioEngine: AVAudioEngine?

    private(set) var isListening: Bool = false
    private var isStopping: Bool = false

    private let baseURL = "wss://api.deepgram.com/v1/listen"

    private var receiveTask: Task<Void, Never>?

    /// Accumulated final transcript segments
    private var finalSegments: [String] = []

    /// Continuation for interim text updates
    private var interimContinuation: AsyncStream<String>.Continuation?

    // MARK: - Public Streams

    nonisolated let interimTextStream: AsyncStream<String>

    // MARK: - Init

    init() {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        self.interimTextStream = stream
        self.interimContinuation = continuation
    }

    // MARK: - Start Listening

    func startListening() async throws {
        guard !isListening else { return }

        guard APIKeys.isDeepgramConfigured else {
            throw DeepgramError.notConfigured
        }

        finalSegments = []
        isStopping = false

        // Configure audio session for recording
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try audioSession.setActive(true)

        // Connect WebSocket with chat-optimized params
        let queryParams = [
            "model=\(NoteVConfig.ChatVoice.model)",
            "sample_rate=\(NoteVConfig.Audio.sampleRate)",
            "channels=1",
            "encoding=linear16",
            "language=en",
            "punctuate=true",
            "smart_format=true",
            "interim_results=true",
            "endpointing=\(NoteVConfig.ChatVoice.endpointingMs)",
            "utterance_end_ms=\(NoteVConfig.ChatVoice.utteranceEndMs)"
        ].joined(separator: "&")

        let urlString = "\(baseURL)?\(queryParams)"
        guard let url = URL(string: urlString) else {
            throw DeepgramError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(APIKeys.deepgramAPIKey)", forHTTPHeaderField: "Authorization")

        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        isListening = true
        startReceiveLoop()
        startAudioCapture()

        NSLog("[DeepgramVoiceService] Started listening")
    }

    // MARK: - Stop Listening

    /// Stop listening and return the full transcript.
    func stopListening() async -> String {
        guard isListening, !isStopping else {
            return finalSegments.joined(separator: " ")
        }

        isListening = false
        isStopping = true

        // Stop audio capture first
        stopAudioCapture()

        // Send Finalize to flush buffered audio
        sendTextMessage("{\"type\": \"Finalize\"}")

        // Wait briefly for final results
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        // Send CloseStream
        sendTextMessage("{\"type\": \"CloseStream\"}")

        // Brief drain
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Cleanup
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        // Finish the interim stream so consumers exit their for-await loop
        interimContinuation?.finish()
        interimContinuation = nil

        let result = finalSegments.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        isStopping = false
        NSLog("[DeepgramVoiceService] Stopped — transcript: '\(result.prefix(80))'")
        return result
    }

    // MARK: - Audio Capture

    private func startAudioCapture() {
        let engine = AVAudioEngine()
        audioEngine = engine

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Convert to 16kHz mono PCM (Deepgram format)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(NoteVConfig.Audio.sampleRate),
            channels: 1,
            interleaved: true
        ) else {
            NSLog("[DeepgramVoiceService] Failed to create target audio format")
            return
        }

        guard let converter = AVAudioConverter(from: recordingFormat, to: targetFormat) else {
            NSLog("[DeepgramVoiceService] Failed to create audio converter")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Convert buffer to 16kHz PCM
            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * Double(NoteVConfig.Audio.sampleRate) / recordingFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCount) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, let data = convertedBuffer.int16Data else { return }

            Task { await self.sendAudioData(data) }
        }

        do {
            try engine.start()
            NSLog("[DeepgramVoiceService] Audio engine started")
        } catch {
            NSLog("[DeepgramVoiceService] Audio engine start failed: \(error.localizedDescription)")
        }
    }

    private func stopAudioCapture() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }

    private func sendAudioData(_ data: Data) {
        guard isListening, let ws = webSocketTask else { return }
        let message = URLSessionWebSocketTask.Message.data(data)
        ws.send(message) { error in
            if let error = error {
                NSLog("[DeepgramVoiceService] Audio send error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Receive Loop

    private func startReceiveLoop() {
        receiveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                guard await self.webSocketTask != nil else { break }

                do {
                    guard let ws = await self.webSocketTask else { break }
                    let message = try await ws.receive()
                    await self.handleMessage(message)
                } catch {
                    if !Task.isCancelled {
                        NSLog("[DeepgramVoiceService] Receive error: \(error.localizedDescription)")
                    }
                    break
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "Results":
            handleResults(json)
        case "UtteranceEnd":
            guard !isStopping else { return } // Prevent double stop
            NSLog("[DeepgramVoiceService] UtteranceEnd — auto-stopping")
            Task { [weak self] in
                _ = await self?.stopListening()
            }
        case "Metadata":
            NSLog("[DeepgramVoiceService] Connected to Deepgram")
        default:
            break
        }
    }

    private func handleResults(_ json: [String: Any]) {
        guard let channel = json["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let best = alternatives.first,
              let transcript = best["transcript"] as? String,
              !transcript.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let isFinal = json["is_final"] as? Bool ?? false

        if isFinal {
            finalSegments.append(transcript)
            let fullText = finalSegments.joined(separator: " ")
            interimContinuation?.yield(fullText)
            NSLog("[DeepgramVoiceService] Final: '\(transcript.prefix(60))'")
        } else {
            // Show interim: accumulated finals + current interim
            let fullText = (finalSegments + [transcript]).joined(separator: " ")
            interimContinuation?.yield(fullText)
        }
    }

    // MARK: - Helpers

    private func sendTextMessage(_ text: String) {
        guard let ws = webSocketTask else { return }
        let message = URLSessionWebSocketTask.Message.string(text)
        ws.send(message) { error in
            if let error = error {
                NSLog("[DeepgramVoiceService] Text send error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - AVAudioPCMBuffer Extension

private extension AVAudioPCMBuffer {
    var int16Data: Data? {
        guard let channelData = int16ChannelData else { return nil }
        let count = Int(frameLength)
        return Data(bytes: channelData[0], count: count * MemoryLayout<Int16>.size)
    }
}
