import Foundation

// MARK: - SessionTranscriptExtractor

/// Transcribes session MP4 audio via Deepgram's pre-recorded REST API.
/// Used when live WebSocket STT fails (common on LTE) but video was captured.
final class SessionTranscriptExtractor {

    enum ExtractionError: Error, LocalizedError {
        case notConfigured
        case invalidURL
        case emptyResponse
        case httpError(Int, String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Deepgram API key not configured"
            case .invalidURL: return "Invalid Deepgram transcription URL"
            case .emptyResponse: return "Deepgram returned no transcript segments"
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

        let queryParams = [
            "model=\(NoteVConfig.Audio.deepgramModel)",
            "language=en",
            "punctuate=true",
            "smart_format=true",
            "utterances=true"
        ].joined(separator: "&")

        let urlString = "https://api.deepgram.com/v1/listen?\(queryParams)"
        guard let url = URL(string: urlString) else {
            throw ExtractionError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(APIKeys.deepgramAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        let fileData = try Data(contentsOf: videoURL)
        NSLog("[SessionTranscriptExtractor] Uploading \(fileData.count) bytes from \(videoURL.lastPathComponent)")

        let (data, response) = try await session.upload(for: request, from: fileData)

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

        NSLog("[SessionTranscriptExtractor] Extracted \(segments.count) segments from MP4")
        return segments
    }

    // MARK: - Response parsing

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

// MARK: - Deepgram pre-recorded response models

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
