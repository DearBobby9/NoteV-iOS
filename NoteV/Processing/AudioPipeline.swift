import Foundation

// MARK: - AudioPipeline

/// Processes raw audio chunks into transcript segments via streaming STT.
/// TODO: Phase 2 — Deepgram WebSocket integration
final class AudioPipeline {

    // MARK: - Properties

    private let deepgramService: DeepgramService
    private var transcriptContinuation: AsyncStream<TranscriptSegment>.Continuation?

    lazy var transcriptStream: AsyncStream<TranscriptSegment> = {
        AsyncStream { continuation in
            self.transcriptContinuation = continuation
        }
    }()

    // MARK: - Init

    init(deepgramService: DeepgramService = DeepgramService()) {
        self.deepgramService = deepgramService
        NSLog("[AudioPipeline] Initialized")
    }

    // MARK: - Processing

    /// Start processing audio chunks from the given stream.
    func startProcessing(audioStream: AsyncStream<AudioChunk>) async {
        NSLog("[AudioPipeline] startProcessing() called")
        // TODO: Phase 2
        // 1. Connect to Deepgram WebSocket via DeepgramService
        // 2. Forward audio chunks to WebSocket
        // 3. Parse STT responses into TranscriptSegments
        // 4. Yield segments to transcriptContinuation
    }

    /// Stop processing and close connections.
    func stop() {
        NSLog("[AudioPipeline] stop() called")
        transcriptContinuation?.finish()
        // TODO: Phase 2 — Close Deepgram WebSocket
    }
}
