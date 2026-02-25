import Foundation
import Speech
import AVFoundation

// MARK: - AudioPipeline

/// Processes raw audio chunks into transcript segments via Apple Speech on-device STT.
/// Auto-restarts recognition when Apple's ~1 minute limit is reached.
final class AudioPipeline {

    // MARK: - Properties

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var transcriptContinuation: AsyncStream<TranscriptSegment>.Continuation?
    private var isProcessing = false
    private var sessionStartTime: Date?

    // Track previous transcription to extract new text
    private var lastTranscriptionText = ""
    private var segmentIndex = 0
    private var restartCount = 0

    // Reference to audio stream for restart
    private var currentAudioStream: AsyncStream<AudioChunk>?
    private var finalResultContinuation: CheckedContinuation<Void, Never>?

    lazy var transcriptStream: AsyncStream<TranscriptSegment> = {
        AsyncStream { continuation in
            self.transcriptContinuation = continuation
        }
    }()

    // MARK: - Init

    init() {
        NSLog("[AudioPipeline] Initialized — using Apple Speech on-device STT")
    }

    // MARK: - Processing

    /// Start processing audio chunks from the given stream.
    func startProcessing(audioStream: AsyncStream<AudioChunk>) async {
        NSLog("[AudioPipeline] startProcessing() called")

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            NSLog("[AudioPipeline] ERROR: Speech recognizer not available")
            return
        }

        // Request authorization
        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        guard authorized else {
            NSLog("[AudioPipeline] ERROR: Speech recognition not authorized")
            return
        }

        isProcessing = true
        sessionStartTime = Date()
        currentAudioStream = audioStream

        startRecognitionSession()

        // Feed audio chunks — blocks until the stream finishes (provider stops).
        // This lets the caller await the pipeline task to know all audio has been fed.
        for await chunk in audioStream {
            guard isProcessing else { break }
            feedAudioChunk(chunk)
        }

        NSLog("[AudioPipeline] Audio feed completed — all chunks delivered to recognition engine")
    }

    /// Phase 1: Stop feeding audio and signal end of input to recognition engine.
    /// Call this after awaiting the pipeline task so all audio has been fed.
    func endAudioInput() {
        NSLog("[AudioPipeline] endAudioInput() called")
        isProcessing = false
        recognitionRequest?.endAudio()
    }

    /// Wait for the active recognition task to deliver its terminal callback.
    /// Uses an event-driven signal with timeout fallback to avoid indefinite hangs.
    func waitForFinalResult(timeoutNanoseconds: UInt64 = 2_000_000_000) async {
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
    }

    /// Phase 2: Cancel recognition and finish the transcript stream.
    /// Call this after a brief delay so the recognition engine can deliver final segments.
    func finishOutputStream() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        transcriptContinuation?.finish()
        signalFinalResultIfNeeded()
        NSLog("[AudioPipeline] Finished — produced \(segmentIndex) segments across \(restartCount + 1) recognition sessions")
    }

    /// Stop immediately (combines both phases). Used for error paths.
    func stop() {
        NSLog("[AudioPipeline] stop() called")
        endAudioInput()
        finishOutputStream()
    }

    // MARK: - Recognition Session

    private func startRecognitionSession() {
        guard isProcessing, let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        // Create new recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 13, *) {
            request.requiresOnDeviceRecognition = true
        }
        self.recognitionRequest = request

        // Reset tracking for new session
        lastTranscriptionText = ""

        NSLog("[AudioPipeline] Starting recognition session #\(restartCount + 1)")

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let newText = result.bestTranscription.formattedString
                let isFinal = result.isFinal

                // Extract only newly added text
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

                    self.transcriptContinuation?.yield(segment)
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

    /// Restart recognition after Apple's ~1 minute limit
    private func restartRecognitionIfNeeded() {
        guard isProcessing else { return }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        restartCount += 1
        NSLog("[AudioPipeline] Restarting recognition (restart #\(restartCount))")

        // Small delay before restart to avoid rapid cycling
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.startRecognitionSession()
        }
    }

    // MARK: - Audio Feeding

    private func feedAudioChunk(_ chunk: AudioChunk) {
        guard let request = recognitionRequest else { return }

        // Convert PCM Int16 Data back to AVAudioPCMBuffer
        let sampleRate = Double(NoteVConfig.Audio.sampleRate)
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        ) else { return }

        let frameCount = AVAudioFrameCount(chunk.data.count / 2) // Int16 = 2 bytes per sample
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        // Copy PCM data into buffer
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
