import AVFoundation
import Foundation

// MARK: - VideoRecorder

/// Writes continuous H.264/AAC MP4 from CMSampleBuffers (phone camera or glasses DAT stream).
final class VideoRecorder: @unchecked Sendable {

    enum VideoRecorderError: Error, LocalizedError {
        case alreadyRecording
        case notRecording
        case writerFailed(String)
        case missingFormat

        var errorDescription: String? {
            switch self {
            case .alreadyRecording: return "Video recording already in progress"
            case .notRecording: return "No active video recording"
            case .writerFailed(let msg): return "Video write failed: \(msg)"
            case .missingFormat: return "Could not read media format from sample buffer"
            }
        }
    }

    private let queue = DispatchQueue(label: "com.notev.videoRecorder")
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var sessionStarted = false
    private var audioSamplesAppended = 0
    private var pendingAudioBuffers: [CMSampleBuffer] = []
    private var sessionStartTime: CMTime?
    private var audioDropLogCount = 0

    // MARK: - Lifecycle

    func startRecording(to url: URL) throws {
        try queue.sync {
            guard assetWriter == nil else { throw VideoRecorderError.alreadyRecording }

            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }

            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            assetWriter = writer
            outputURL = url
            sessionStarted = false
            videoInput = nil
            audioInput = nil
            audioSamplesAppended = 0
            pendingAudioBuffers = []
            sessionStartTime = nil
            audioDropLogCount = 0

            // Audio track must exist before startWriting() — video samples usually arrive first.
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: NoteVConfig.Audio.muxSampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128_000
            ]
            let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioIn.expectsMediaDataInRealTime = true
            guard writer.canAdd(audioIn) else {
                throw VideoRecorderError.writerFailed("cannot add audio track")
            }
            writer.add(audioIn)
            audioInput = audioIn
            NSLog("[VideoRecorder] Audio track pre-configured — \(NoteVConfig.Audio.muxSampleRate)Hz 1ch AAC")

            NSLog("[VideoRecorder] Started — output: \(url.lastPathComponent)")
        }
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        queue.async { [weak self] in
            self?.appendSampleBuffer(sampleBuffer, mediaType: .video)
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        queue.async { [weak self] in
            self?.appendSampleBuffer(sampleBuffer, mediaType: .audio)
        }
    }

    /// Number of audio samples successfully muxed into the MP4.
    var muxedAudioSampleCount: Int {
        queue.sync { audioSamplesAppended }
    }

    /// Blocks until all previously dispatched append operations complete.
    func waitForPendingAppends() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                continuation.resume()
            }
        }
    }

    func finishRecording() async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self, let writer = self.assetWriter, let url = self.outputURL else {
                    continuation.resume(returning: nil)
                    return
                }

                guard self.sessionStarted else {
                    self.reset()
                    NSLog("[VideoRecorder] No frames written — discarding empty file")
                    try? FileManager.default.removeItem(at: url)
                    continuation.resume(returning: nil)
                    return
                }

                try? self.flushPendingAudioBuffers()

                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()

                if self.audioSamplesAppended == 0 {
                    NSLog("[VideoRecorder] WARNING: Audio track configured but no audio samples were muxed")
                } else {
                    NSLog("[VideoRecorder] Muxed \(self.audioSamplesAppended) audio samples")
                }

                writer.finishWriting {
                    let status = writer.status
                    let errorMessage = writer.error?.localizedDescription ?? "unknown"
                    self.reset()

                    if status == .completed {
                        NSLog("[VideoRecorder] Finished — saved \(url.lastPathComponent)")
                        continuation.resume(returning: url)
                    } else {
                        try? FileManager.default.removeItem(at: url)
                        continuation.resume(throwing: VideoRecorderError.writerFailed(errorMessage))
                    }
                }
            }
        }
    }

    // MARK: - Private

    private func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer, mediaType: AVMediaType) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        do {
            try configureInputIfNeeded(for: sampleBuffer, mediaType: mediaType)

            if mediaType == .audio, videoInput == nil {
                pendingAudioBuffers.append(sampleBuffer)
                trimPendingAudioBuffersIfNeeded()
                return
            }

            try startSessionIfNeeded(with: sampleBuffer)

            guard let writer = assetWriter, writer.status != .failed else {
                throw VideoRecorderError.writerFailed(assetWriter?.error?.localizedDescription ?? "writer failed")
            }

            try appendToInput(sampleBuffer, mediaType: mediaType)
            try flushPendingAudioBuffers()
        } catch {
            NSLog("[VideoRecorder] ERROR appending \(mediaType.rawValue): \(error.localizedDescription)")
        }
    }

    private func appendToInput(_ sampleBuffer: CMSampleBuffer, mediaType: AVMediaType) throws {
        guard let writer = assetWriter, writer.status != .failed else {
            throw VideoRecorderError.writerFailed(assetWriter?.error?.localizedDescription ?? "writer failed")
        }

        let input = mediaType == .video ? videoInput : audioInput
        guard let input else { return }

        guard input.isReadyForMoreMediaData else {
            if mediaType == .audio {
                pendingAudioBuffers.append(sampleBuffer)
                trimPendingAudioBuffersIfNeeded()
                if audioDropLogCount < 3 {
                    audioDropLogCount += 1
                    NSLog("[VideoRecorder] Audio input not ready — buffering sample (\(pendingAudioBuffers.count) queued)")
                }
            }
            return
        }

        if !input.append(sampleBuffer) {
            throw VideoRecorderError.writerFailed("append returned false for \(mediaType.rawValue)")
        }

        if mediaType == .audio {
            audioSamplesAppended += 1
        }
    }

    private func flushPendingAudioBuffers() throws {
        guard sessionStarted, let audioInput else { return }

        while !pendingAudioBuffers.isEmpty, audioInput.isReadyForMoreMediaData {
            let buffer = pendingAudioBuffers.removeFirst()
            if !audioInput.append(buffer) {
                pendingAudioBuffers.insert(buffer, at: 0)
                throw VideoRecorderError.writerFailed("append returned false for pending audio")
            }
            audioSamplesAppended += 1
        }
    }

    private func trimPendingAudioBuffersIfNeeded() {
        let maxPending = NoteVConfig.Video.maxPendingAudioBuffers
        if pendingAudioBuffers.count > maxPending {
            pendingAudioBuffers.removeFirst(pendingAudioBuffers.count - maxPending)
            if audioDropLogCount < 5 {
                audioDropLogCount += 1
                NSLog("[VideoRecorder] WARNING: Audio buffer overflow — dropped oldest samples")
            }
        }
    }

    private func configureInputIfNeeded(for sampleBuffer: CMSampleBuffer, mediaType: AVMediaType) throws {
        guard let writer = assetWriter else { throw VideoRecorderError.notRecording }

        if mediaType == .video, videoInput == nil {
            guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else {
                throw VideoRecorderError.missingFormat
            }
            let dimensions = CMVideoFormatDescriptionGetDimensions(format)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(dimensions.width),
                AVVideoHeightKey: Int(dimensions.height)
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else {
                throw VideoRecorderError.writerFailed("cannot add video track")
            }
            writer.add(input)
            videoInput = input
        }

        // Audio input is pre-configured in startRecording().
    }

    private func startSessionIfNeeded(with sampleBuffer: CMSampleBuffer) throws {
        guard let writer = assetWriter, !sessionStarted else { return }
        guard videoInput != nil else { return }

        var startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if !pendingAudioBuffers.isEmpty,
           let firstAudio = pendingAudioBuffers.first {
            let audioTime = CMSampleBufferGetPresentationTimeStamp(firstAudio)
            if audioTime < startTime {
                startTime = audioTime
            }
        }

        guard writer.startWriting() else {
            throw VideoRecorderError.writerFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }
        writer.startSession(atSourceTime: startTime)
        sessionStarted = true
        sessionStartTime = startTime
        try flushPendingAudioBuffers()
    }

    private func reset() {
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        outputURL = nil
        sessionStarted = false
        audioSamplesAppended = 0
        pendingAudioBuffers = []
        sessionStartTime = nil
        audioDropLogCount = 0
    }
}
