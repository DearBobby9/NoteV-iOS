import AVFoundation
import Foundation

// MARK: - SessionTranscriptExtractor

/// Transcribes session MP4 audio via Deepgram's pre-recorded REST API.
/// Used when live WebSocket STT fails (common on LTE) but video was captured.
final class SessionTranscriptExtractor {

    enum ExtractionError: Error, LocalizedError {
        case notConfigured
        case invalidURL
        case emptyResponse
        case noAudioTrack
        case audioExportFailed(String)
        case httpError(Int, String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Deepgram API key not configured"
            case .invalidURL: return "Invalid Deepgram transcription URL"
            case .emptyResponse: return "Deepgram returned no transcript segments"
            case .noAudioTrack: return "Session video has no audio track"
            case .audioExportFailed(let msg): return "Could not extract audio from session video: \(msg)"
            case .httpError(let code, let body): return "Deepgram HTTP \(code): \(body.prefix(200))"
            }
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Transcribe audio from a session MP4 and return timed segments.
    func extract(from videoURL: URL) async throws -> [TranscriptSegment] {
        guard APIKeys.isDeepgramConfigured else {
            throw ExtractionError.notConfigured
        }

        let started = Date()
        let (uploadData, contentType, sourceLabel) = try await prepareUploadPayload(from: videoURL)

        let detectEncoding = contentType == "video/mp4" ? "&detect_encoding=true" : ""
        let queryParams = [
            "model=\(NoteVConfig.Audio.deepgramModel)",
            "language=en",
            "punctuate=true",
            "smart_format=true",
            "utterances=true"
        ].joined(separator: "&")

        let urlString = "https://api.deepgram.com/v1/listen?\(queryParams)\(detectEncoding)"
        guard let url = URL(string: urlString) else {
            throw ExtractionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(APIKeys.deepgramAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        NSLog("[SessionTranscriptExtractor] Uploading \(uploadData.count) bytes (\(contentType), \(sourceLabel)) from \(videoURL.lastPathComponent)")

        let (data, response) = try await session.upload(for: request, from: uploadData)
        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)

        guard let http = response as? HTTPURLResponse else {
            throw ExtractionError.emptyResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw ExtractionError.httpError(http.statusCode, body)
        }

        let segments = try Self.parseSegments(from: data)
        guard !segments.isEmpty else {
            throw ExtractionError.emptyResponse
        }

        NSLog("[SessionTranscriptExtractor] Extracted \(segments.count) segments from MP4 in \(elapsedMs)ms")
        return segments
    }

    // MARK: - Audio export

    private func prepareUploadPayload(from videoURL: URL) async throws -> (Data, String, String) {
        let asset = AVURLAsset(url: videoURL)
        let videoDuration = try await asset.load(.duration).seconds

        do {
            let audioURL = try await exportAudio(from: videoURL)
            defer { try? FileManager.default.removeItem(at: audioURL) }
            let data = try Data(contentsOf: audioURL)
            let audioDuration = try await Self.audioTrackDuration(in: asset)
            try Self.validateAudioPayload(data: data, audioDuration: audioDuration, videoDuration: videoDuration)
            NSLog("[SessionTranscriptExtractor] M4A export valid — \(data.count) bytes, \(String(format: "%.1f", audioDuration))s audio")
            return (data, "audio/m4a", "m4a-export")
        } catch {
            NSLog("[SessionTranscriptExtractor] M4A export failed — trying PCM/WAV: \(error.localizedDescription)")
        }

        do {
            let wavData = try await extractPCMAsWAV(from: videoURL)
            let audioDuration = try await Self.audioTrackDuration(in: asset)
            try Self.validateAudioPayload(data: wavData, audioDuration: audioDuration, videoDuration: videoDuration)
            NSLog("[SessionTranscriptExtractor] PCM/WAV extraction valid — \(wavData.count) bytes")
            return (wavData, "audio/wav", "pcm-wav")
        } catch {
            NSLog("[SessionTranscriptExtractor] PCM/WAV failed — uploading full MP4: \(error.localizedDescription)")
        }

        let data = try Data(contentsOf: videoURL)
        return (data, "video/mp4", "full-mp4-fallback")
    }

    private func exportAudio(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            throw ExtractionError.noAudioTrack
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ExtractionError.audioExportFailed("Could not create export session")
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notev-audio-\(UUID().uuidString).m4a")
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exportSession.exportAsynchronously {
                continuation.resume()
            }
        }

        guard exportSession.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            let message = exportSession.error?.localizedDescription ?? "export status \(exportSession.status.rawValue)"
            throw ExtractionError.audioExportFailed(message)
        }

        return outputURL
    }

    private func extractPCMAsWAV(from videoURL: URL) async throws -> Data {
        let asset = AVURLAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = audioTracks.first else {
            throw ExtractionError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: NoteVConfig.Audio.sampleRate,
            AVNumberOfChannelsKey: NoteVConfig.Audio.channels
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw ExtractionError.audioExportFailed("Cannot add AVAssetReader output")
        }
        reader.add(output)
        guard reader.startReading() else {
            throw ExtractionError.audioExportFailed(reader.error?.localizedDescription ?? "AVAssetReader failed to start")
        }

        var pcmData = Data()
        while reader.status == .reading {
            guard let sampleBuffer = output.copyNextSampleBuffer(),
                  let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                continue
            }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(
                blockBuffer,
                atOffset: 0,
                lengthAtOffsetOut: nil,
                totalLengthOut: &length,
                dataPointerOut: &dataPointer
            ) == noErr,
                  let dataPointer else {
                continue
            }
            pcmData.append(UnsafeBufferPointer(start: dataPointer, count: length))
        }

        if reader.status == .failed {
            throw ExtractionError.audioExportFailed(reader.error?.localizedDescription ?? "AVAssetReader failed")
        }

        guard !pcmData.isEmpty else {
            throw ExtractionError.audioExportFailed("PCM extraction produced no data")
        }

        return Self.wrapPCMAsWAV(
            pcmData: pcmData,
            sampleRate: NoteVConfig.Audio.sampleRate,
            channels: NoteVConfig.Audio.channels
        )
    }

    // MARK: - Validation helpers (testable)

    static func validateAudioPayload(data: Data, audioDuration: TimeInterval, videoDuration: TimeInterval) throws {
        guard data.count >= NoteVConfig.TranscriptExtraction.minExportBytes else {
            throw ExtractionError.audioExportFailed("Exported audio too small (\(data.count) bytes)")
        }
        guard videoDuration <= 0 || audioDuration >= videoDuration * NoteVConfig.TranscriptExtraction.minAudioDurationRatio else {
            throw ExtractionError.audioExportFailed(
                "Audio track too short (\(String(format: "%.1f", audioDuration))s vs \(String(format: "%.1f", videoDuration))s video)"
            )
        }
    }

    static func audioTrackDuration(in asset: AVURLAsset) async throws -> TimeInterval {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { return 0 }
        let duration = try await track.load(.timeRange).duration
        return duration.seconds
    }

    static func wrapPCMAsWAV(pcmData: Data, sampleRate: Int, channels: Int) -> Data {
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        header.append(UInt32(36 + pcmData.count).littleEndianData)
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        header.append(UInt32(16).littleEndianData)
        header.append(UInt16(1).littleEndianData)
        header.append(UInt16(channels).littleEndianData)
        header.append(UInt32(sampleRate).littleEndianData)
        header.append(UInt32(byteRate).littleEndianData)
        header.append(UInt16(blockAlign).littleEndianData)
        header.append(UInt16(bitsPerSample).littleEndianData)
        header.append(contentsOf: "data".utf8)
        header.append(UInt32(pcmData.count).littleEndianData)
        header.append(pcmData)
        return header
    }

    static func parseSegments(from data: Data) throws -> [TranscriptSegment] {
        let response = try JSONDecoder().decode(PrerecordedResponse.self, from: data)

        if let utterances = response.results?.utterances, !utterances.isEmpty {
            return utterances.compactMap { utterance in
                let text = utterance.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return TranscriptSegment(
                    startTime: utterance.start,
                    endTime: utterance.end,
                    text: text,
                    isFinal: true
                )
            }
        }

        if let words = response.results?.channels.first?.alternatives.first?.words, !words.isEmpty {
            return groupWordsIntoSegments(words)
        }

        if let transcript = response.results?.channels.first?.alternatives.first?.transcript {
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return [TranscriptSegment(startTime: 0, endTime: 0, text: text, isFinal: true)]
            }
        }

        return []
    }

    private static func groupWordsIntoSegments(_ words: [PrerecordedWord]) -> [TranscriptSegment] {
        let pauseThreshold: TimeInterval = 0.8
        var segments: [TranscriptSegment] = []
        var currentWords: [PrerecordedWord] = []

        func flush() {
            guard !currentWords.isEmpty else { return }
            let text = currentWords.map(\.word).joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                currentWords = []
                return
            }
            let start = currentWords.first?.start ?? 0
            let end = currentWords.last?.end ?? start
            segments.append(TranscriptSegment(startTime: start, endTime: end, text: text, isFinal: true))
            currentWords = []
        }

        for word in words {
            if let last = currentWords.last, word.start - last.end > pauseThreshold {
                flush()
            }
            currentWords.append(word)
        }
        flush()
        return segments
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        withUnsafeBytes(of: littleEndian) { Data($0) }
    }
}

private extension CMTime {
    var seconds: TimeInterval {
        CMTimeGetSeconds(self)
    }
}

private struct PrerecordedResponse: Decodable {
    let results: PrerecordedResults?
}

private struct PrerecordedResults: Decodable {
    let channels: [PrerecordedChannel]
    let utterances: [PrerecordedUtterance]?
}

private struct PrerecordedChannel: Decodable {
    let alternatives: [PrerecordedAlternative]
}

private struct PrerecordedAlternative: Decodable {
    let transcript: String
    let words: [PrerecordedWord]?
}

private struct PrerecordedUtterance: Decodable {
    let start: TimeInterval
    let end: TimeInterval
    let transcript: String
}

private struct PrerecordedWord: Decodable {
    let word: String
    let start: TimeInterval
    let end: TimeInterval
}
