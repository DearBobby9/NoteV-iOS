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
    private var deepgramConnectTask: Task<DeepgramService?, Never>?

    /// Eagerly initialized transcript stream (thread-safe, no lazy var hazard)
    let transcriptStream: AsyncStream<TranscriptSegment>

    /// MainActor callback for live STT UI state.
    var onLiveTranscriptStatusChange: (@MainActor (LiveTranscriptStatus) -> Void)?

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
        deepgramConnectTask?.cancel()
        deepgramConnectTask = nil

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
    func finishOutputStream() async {
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
            if let service = deepgramService {
                await service.disconnect()
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
        Task { await finishOutputStream() }
    }

    // MARK: - Deepgram Processing

    private func startDeepgramProcessing(audioStream: AsyncStream<AudioChunk>) async {
        let coordinator = DeepgramFeedCoordinator()
        var midSessionReconnects = 0
        var liveUnavailable = false

        reportLiveStatus(.connecting)

        let connectTask = Task { [weak self] () -> DeepgramService? in
            guard let self else { return nil }
            guard await self.connectDeepgramWithRetry(maxAttempts: 3, coordinator: coordinator) else { return nil }
            return self.deepgramService
        }
        deepgramConnectTask = connectTask

        for await chunk in audioStream {
            guard isProcessing else { break }
            if liveUnavailable { continue }

            if let service = coordinator.service ?? deepgramService {
                if !(await activateDeepgramService(service, coordinator: coordinator)) {
                    liveUnavailable = true
                    reportLiveStatus(.unavailable)
                    continue
                }

                if !(await service.isConnected) {
                    let reconnected = await attemptMidSessionReconnect(
                        coordinator: coordinator,
                        midSessionReconnects: &midSessionReconnects
                    )
                    if !reconnected {
                        liveUnavailable = true
                        reportLiveStatus(.unavailable)
                        continue
                    }
                }

                guard let activeService = deepgramService else { continue }
                let sent = await activeService.sendAudio(chunk)
                if !sent {
                    let reconnected = await attemptMidSessionReconnect(
                        coordinator: coordinator,
                        midSessionReconnects: &midSessionReconnects
                    )
                    if reconnected, let retryService = deepgramService {
                        _ = await retryService.sendAudio(chunk)
                        reportLiveStatus(.streaming)
                    } else {
                        liveUnavailable = true
                        reportLiveStatus(.unavailable)
                    }
                }
            } else {
                coordinator.appendPending(chunk, maxCount: NoteVConfig.Audio.deepgramConnectBufferMaxChunks)
                if deepgramService == nil, coordinator.service == nil {
                    if let service = await connectTask.value {
                        if !(await activateDeepgramService(service, coordinator: coordinator)) {
                            liveUnavailable = true
                            reportLiveStatus(.unavailable)
                        }
                    } else {
                        liveUnavailable = true
                        reportLiveStatus(.unavailable)
                    }
                }
            }
        }

        if deepgramService == nil, let service = await connectTask.value {
            guard await activateDeepgramService(service, coordinator: coordinator) else {
                reportLiveStatus(.unavailable)
                return
            }
            for buffered in coordinator.takePending() {
                guard isProcessing, !liveUnavailable else { break }
                if !(await service.sendAudio(buffered)) {
                    reportLiveStatus(.unavailable)
                    break
                }
            }
        }

        NSLog("[AudioPipeline] Audio feed completed — all chunks sent to Deepgram")
    }

    private func attemptMidSessionReconnect(
        coordinator: DeepgramFeedCoordinator,
        midSessionReconnects: inout Int
    ) async -> Bool {
        if midSessionReconnects >= NoteVConfig.Audio.deepgramMidSessionReconnectMax {
            return false
        }
        midSessionReconnects += 1
        NSLog("[AudioPipeline] Mid-session Deepgram reconnect attempt \(midSessionReconnects)")

        deepgramBridgeTask?.cancel()
        deepgramBridgeTask = nil
        if let service = deepgramService {
            await service.disconnect()
        }
        deepgramService = nil
        coordinator.setService(nil)

        coordinator.resetBridge()

        reportLiveStatus(.connecting)
        guard await connectDeepgramWithRetry(maxAttempts: 2, coordinator: coordinator),
              let service = deepgramService else {
            return false
        }
        return await activateDeepgramService(service, coordinator: coordinator)
    }

    private func reportLiveStatus(_ status: LiveTranscriptStatus) {
        guard let onLiveTranscriptStatusChange else { return }
        Task { @MainActor in
            onLiveTranscriptStatusChange(status)
        }
    }

    private func activateDeepgramService(_ service: DeepgramService, coordinator: DeepgramFeedCoordinator) async -> Bool {
        deepgramService = service

        if coordinator.markBridgeStarted() {
            deepgramBridgeTask = Task { [weak self] in
                for await segment in service.transcriptStream {
                    guard let self = self else { break }
                    self.segmentIndex += 1
                    self.transcriptContinuation.yield(segment)
                }
                NSLog("[AudioPipeline] Deepgram transcript bridge ended")
            }
        }

        for buffered in coordinator.takePending() {
            guard isProcessing else { break }
            if !(await service.sendAudio(buffered)) {
                return false
            }
        }
        return true
    }

    private func connectDeepgramWithRetry(maxAttempts: Int, coordinator: DeepgramFeedCoordinator) async -> Bool {
        for attempt in 1...maxAttempts {
            if Task.isCancelled || !isProcessing { return false }
            let service = DeepgramService()
            deepgramService = service

            do {
                try await service.connect()
                await service.setOnConnectionLost { reason in
                    NSLog("[AudioPipeline] Deepgram connection lost callback: \(reason)")
                }
                coordinator.setService(service)
                NSLog("[AudioPipeline] Deepgram connected — streaming audio (attempt \(attempt))")
                return true
            } catch {
                NSLog("[AudioPipeline] ERROR: Deepgram connect failed (attempt \(attempt)): \(error.localizedDescription)")
                await service.disconnect()
                deepgramService = nil
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
                }
            }
        }
        deepgramBridgeTask?.cancel()
        deepgramBridgeTask = nil
        return false
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

// MARK: - DeepgramFeedCoordinator

/// Thread-safe buffer used while Deepgram WebSocket connects in parallel with audio capture.
private final class DeepgramFeedCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var _service: DeepgramService?
    private var _pending: [AudioChunk] = []
    private var _bridgeStarted = false

    var service: DeepgramService? {
        lock.lock()
        defer { lock.unlock() }
        return _service
    }

    func setService(_ service: DeepgramService?) {
        lock.lock()
        _service = service
        lock.unlock()
    }

    func appendPending(_ chunk: AudioChunk, maxCount: Int) {
        lock.lock()
        _pending.append(chunk)
        if _pending.count > maxCount {
            _pending.removeFirst(_pending.count - maxCount)
        }
        lock.unlock()
    }

    func takePending() -> [AudioChunk] {
        lock.lock()
        defer { lock.unlock() }
        let chunks = _pending
        _pending = []
        return chunks
    }

    func markBridgeStarted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if _bridgeStarted { return false }
        _bridgeStarted = true
        return true
    }

    func resetBridge() {
        lock.lock()
        _bridgeStarted = false
        lock.unlock()
    }
}
