import Foundation
import Speech
import AVFoundation

// MARK: - AudioPipeline

/// Processes raw audio chunks into transcript segments via the configured STT provider.
/// Supports Apple Speech (on-device) and Deepgram (cloud WebSocket).
/// Auto-restarts recognition when Apple's ~1 minute limit is reached (Apple Speech only).
final class AudioPipeline {

    // MARK: - Properties

    // Apple Speech properties
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // Deepgram property
    private var deepgramService: DeepgramService?

    private let transcriptContinuation: AsyncStream<TranscriptSegment>.Continuation
    private var isProcessing = false
    private var sessionStartTime: Date?

    // Track previous transcription to extract new text (Apple Speech only)
    private var lastTranscriptionText = ""
    private var segmentIndex = 0
    private var restartCount = 0

    // Reference to audio stream for restart (Apple Speech only)
    private var currentAudioStream: AsyncStream<AudioChunk>?
    private var finalResultContinuation: CheckedContinuation<Void, Never>?

    // Deepgram transcript bridge task
    private var deepgramBridgeTask: Task<Void, Never>?

    /// Eagerly initialized transcript stream (thread-safe, no lazy var hazard)
    let transcriptStream: AsyncStream<TranscriptSegment>

    // MARK: - Init

    init() {
        let (stream, continuation) = AsyncStream<TranscriptSegment>.makeStream()
        self.transcriptStream = stream
        self.transcriptContinuation = continuation

        let provider = NoteVConfig.Audio.sttProvider
        NSLog("[AudioPipeline] Initialized — using \(provider.rawValue) STT")
    }

    // MARK: - Processing

    /// Start processing audio chunks from the given stream.
    func startProcessing(audioStream: AsyncStream<AudioChunk>) async {
        NSLog("[AudioPipeline] startProcessing() called — provider: \(NoteVConfig.Audio.sttProvider.rawValue)")

        isProcessing = true
        sessionStartTime = Date()

        switch NoteVConfig.Audio.sttProvider {
        case .appleSpeech:
            await startAppleSpeechProcessing(audioStream: audioStream)
        case .deepgram:
            await startDeepgramProcessing(audioStream: audioStream)
        }
    }

    /// Phase 1: Stop feeding audio and signal end of input to recognition engine.
    func endAudioInput() {
        NSLog("[AudioPipeline] endAudioInput() called — provider: \(NoteVConfig.Audio.sttProvider.rawValue)")
        isProcessing = false

        switch NoteVConfig.Audio.sttProvider {
        case .appleSpeech:
            recognitionRequest?.endAudio()
        case .deepgram:
            // sendFinalize is actor-isolated; fire-and-forget via Task
            if let service = deepgramService {
                Task { await service.sendFinalize() }
            }
        }
    }

    /// Wait for the active recognition to deliver its terminal result.
    func waitForFinalResult(timeoutNanoseconds: UInt64 = 2_000_000_000) async {
        switch NoteVConfig.Audio.sttProvider {
        case .appleSpeech:
            guard recognitionTask != nil else { return }
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    await self?.waitForFinalResultSignal()
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                }
                _ = await group.next()
                group.cancelAll()
            }

        case .deepgram:
            guard let service = deepgramService else { return }
            await service.sendCloseStream()
        }
    }

    /// Phase 2: Cancel recognition and finish the transcript stream.
    func finishOutputStream() {
        switch NoteVConfig.Audio.sttProvider {
        case .appleSpeech:
            recognitionTask?.cancel()
            recognitionTask = nil
            recognitionRequest = nil
            transcriptContinuation.finish()
            signalFinalResultIfNeeded()
            NSLog("[AudioPipeline] Finished — produced \(segmentIndex) segments across \(restartCount + 1) recognition sessions")

        case .deepgram:
            deepgramBridgeTask?.cancel()
            deepgramBridgeTask = nil
            // disconnect is actor-isolated; fire-and-forget via Task
            if let service = deepgramService {
                Task { await service.disconnect() }
            }
            deepgramService = nil
            transcriptContinuation.finish()
            NSLog("[AudioPipeline] Finished — produced \(segmentIndex) Deepgram segments")
        }
    }

    /// Stop immediately (combines both phases). Used for error paths.
    func stop() {
        NSLog("[AudioPipeline] stop() called")
        endAudioInput()
        finishOutputStream()
    }

    // MARK: - Deepgram Processing

    private func startDeepgramProcessing(audioStream: AsyncStream<AudioChunk>) async {
        let service = DeepgramService()
        self.deepgramService = service

        // nonisolated property — safe to access without await
        let dgTranscriptStream = service.transcriptStream

        // Bridge: forward Deepgram segments to AudioPipeline's transcriptStream
        deepgramBridgeTask = Task { [weak self] in
            for await segment in dgTranscriptStream {
                guard let self = self else { break }
                self.segmentIndex += 1
                self.transcriptContinuation.yield(segment)
            }
            NSLog("[AudioPipeline] Deepgram transcript bridge ended")
        }

        do {
            try await service.connect()
            NSLog("[AudioPipeline] Deepgram connected — streaming audio")
        } catch {
            NSLog("[AudioPipeline] ERROR: Deepgram connect failed: \(error.localizedDescription)")
            deepgramBridgeTask?.cancel()
            deepgramBridgeTask = nil
            return
        }

        // Feed audio chunks to Deepgram — blocks until stream finishes
        // sendAudio is async (actor-isolated) which provides natural backpressure
        for await chunk in audioStream {
            guard isProcessing else { break }
            await service.sendAudio(chunk)
        }

        NSLog("[AudioPipeline] Audio feed completed — all chunks sent to Deepgram")
    }

    // MARK: - Apple Speech Processing

    private func startAppleSpeechProcessing(audioStream: AsyncStream<AudioChunk>) async {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            NSLog("[AudioPipeline] ERROR: Speech recognizer not available")
            return
        }

        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        guard authorized else {
            NSLog("[AudioPipeline] ERROR: Speech recognition not authorized")
            return
        }

        currentAudioStream = audioStream
        startRecognitionSession()

        for await chunk in audioStream {
            guard isProcessing else { break }
            feedAudioChunk(chunk)
        }

        NSLog("[AudioPipeline] Audio feed completed — all chunks delivered to recognition engine")
    }

    // MARK: - Recognition Session (Apple Speech)

    private func startRecognitionSession() {
        guard isProcessing, let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 13, *) {
            request.requiresOnDeviceRecognition = true
        }
        self.recognitionRequest = request

        lastTranscriptionText = ""

        NSLog("[AudioPipeline] Starting recognition session #\(restartCount + 1)")

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let newText = result.bestTranscription.formattedString
                let isFinal = result.isFinal

                let addedText: String
                if newText.hasPrefix(self.lastTranscriptionText) {
                    addedText = String(newText.dropFirst(self.lastTranscriptionText.count)).trimmingCharacters(in: .whitespaces)
                } else {
                    addedText = newText
                }

                if !addedText.isEmpty {
                    let timestamp = self.currentTimestamp()
                    self.segmentIndex += 1

                    let segment = TranscriptSegment(
                        startTime: max(0, timestamp - 1.0),
                        endTime: timestamp,
                        text: addedText,
                        isFinal: isFinal
                    )

                    self.transcriptContinuation.yield(segment)
                    NSLog("[AudioPipeline] Segment #\(self.segmentIndex): \"\(addedText)\" (final: \(isFinal))")
                }

                self.lastTranscriptionText = newText

                if isFinal {
                    NSLog("[AudioPipeline] Recognition session ended (final result)")
                    if self.isProcessing {
                        self.restartRecognitionIfNeeded()
                    } else {
                        self.recognitionTask?.cancel()
                        self.recognitionTask = nil
                        self.recognitionRequest = nil
                        self.signalFinalResultIfNeeded()
                    }
                }
            }

            if let error = error {
                NSLog("[AudioPipeline] Recognition error: \(error.localizedDescription)")
                if self.isProcessing {
                    self.restartRecognitionIfNeeded()
                } else {
                    self.recognitionTask = nil
                    self.recognitionRequest = nil
                    self.signalFinalResultIfNeeded()
                }
            }
        }
    }

    private func restartRecognitionIfNeeded() {
        guard isProcessing else { return }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        restartCount += 1
        NSLog("[AudioPipeline] Restarting recognition (restart #\(restartCount))")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.startRecognitionSession()
        }
    }

    // MARK: - Audio Feeding (Apple Speech)

    private func feedAudioChunk(_ chunk: AudioChunk) {
        guard let request = recognitionRequest else { return }

        let sampleRate = Double(NoteVConfig.Audio.sampleRate)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else { return }

        let frameCount = AVAudioFrameCount(chunk.data.count / 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        chunk.data.withUnsafeBytes { rawBuffer in
            guard let src = rawBuffer.baseAddress else { return }
            if let dst = buffer.int16ChannelData?[0] {
                memcpy(dst, src, chunk.data.count)
            }
        }

        request.append(buffer)
    }

    // MARK: - Helpers

    private func currentTimestamp() -> TimeInterval {
        guard let start = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    private func waitForFinalResultSignal() async {
        await withCheckedContinuation { continuation in
            if recognitionTask == nil {
                continuation.resume()
            } else {
                finalResultContinuation = continuation
            }
        }
    }

    private func signalFinalResultIfNeeded() {
        finalResultContinuation?.resume()
        finalResultContinuation = nil
    }
}
