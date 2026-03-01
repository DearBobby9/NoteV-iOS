import Foundation

// MARK: - PolishedTranscriptParser

/// Parses the JSON array response from LLM transcript polishing.
final class PolishedTranscriptParser {

    // MARK: - Decodable Model

    private struct PolishedEntry: Decodable {
        let startTime: Double
        let endTime: Double
        let text: String
    }

    // MARK: - Parse

    /// Parse a JSON string response into PolishedSegments.
    /// Handles markdown code fences, whitespace, and minor formatting issues.
    func parse(jsonString: String) throws -> [PolishedSegment] {
        let cleaned = stripCodeFences(jsonString)

        guard let data = cleaned.data(using: .utf8) else {
            throw PolishParseError.invalidEncoding
        }

        let entries: [PolishedEntry]
        do {
            entries = try JSONDecoder().decode([PolishedEntry].self, from: data)
        } catch {
            NSLog("[PolishedTranscriptParser] JSON decode failed: \(error.localizedDescription)")
            NSLog("[PolishedTranscriptParser] Raw input (first 500 chars): \(cleaned.prefix(500))")
            throw PolishParseError.jsonDecodeFailed(error.localizedDescription)
        }

        // Convert to PolishedSegments, filtering out empty text
        let segments = entries.compactMap { entry -> PolishedSegment? in
            let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            guard entry.endTime >= entry.startTime else { return nil }

            return PolishedSegment(
                startTime: entry.startTime,
                endTime: max(entry.endTime, entry.startTime + 0.1),
                text: text
            )
        }

        NSLog("[PolishedTranscriptParser] Parsed \(entries.count) entries → \(segments.count) valid segments")
        return segments.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Helpers

    /// Strip markdown code fences (```json ... ```) if present.
    private func stripCodeFences(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove leading ```json or ```
        if text.hasPrefix("```") {
            if let newlineIndex = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: newlineIndex)...])
            }
        }

        // Remove trailing ```
        if text.hasSuffix("```") {
            text = String(text.dropLast(3))
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - PolishParseError

enum PolishParseError: LocalizedError {
    case invalidEncoding
    case jsonDecodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidEncoding: return "Could not encode response as UTF-8"
        case .jsonDecodeFailed(let msg): return "JSON decode failed: \(msg)"
        }
    }
}
