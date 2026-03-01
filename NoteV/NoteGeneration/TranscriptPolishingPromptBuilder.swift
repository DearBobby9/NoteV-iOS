import Foundation

// MARK: - TranscriptPolishingPromptBuilder

/// Builds prompts for LLM transcript polishing.
/// Sends raw STT segments as JSON, receives cleaned-up segments as JSON.
enum TranscriptPolishingPromptBuilder {

    // MARK: - System Prompt

    static let systemPrompt = """
    You are a transcript editor. Your job is to clean up raw speech-to-text output \
    while PRESERVING the speaker's original words and meaning.

    Rules:
    1. Remove filler words (um, uh, like, you know) ONLY when they don't carry meaning.
    2. Fix obvious STT misrecognitions (e.g. "neural net works" → "neural networks").
    3. Merge short fragments into complete sentences where natural.
    4. Add proper sentence boundaries and capitalization.
    5. DO NOT paraphrase, summarize, or add content that wasn't spoken.
    6. DO NOT change technical terms, proper nouns, or domain-specific vocabulary.
    7. Keep the speaker's voice and style — informal is OK.
    8. If a fragment is unintelligible or too short to clean up, keep it as-is.

    Output format: JSON array only. Each element has "startTime", "endTime", "text".
    You may merge adjacent segments into one if they form a natural sentence, \
    but use the startTime of the first and the endTime of the last.
    Do NOT output anything other than the JSON array — no explanation, no markdown fences.
    """

    // MARK: - Build Chunk Prompt

    /// Build a user prompt for one chunk of transcript segments.
    static func buildChunkPrompt(segments: [TranscriptSegment]) -> String {
        var jsonArray: [[String: Any]] = []
        for segment in segments {
            jsonArray.append([
                "startTime": round(segment.startTime * 10) / 10,
                "endTime": round(segment.endTime * 10) / 10,
                "text": segment.text
            ])
        }

        guard let data = try? JSONSerialization.data(withJSONObject: jsonArray, options: [.sortedKeys]),
              let jsonString = String(data: data, encoding: .utf8) else {
            // Fallback: build manually
            let manual = segments.map { seg in
                "{\"startTime\":\(seg.startTime),\"endTime\":\(seg.endTime),\"text\":\"\(seg.text.replacingOccurrences(of: "\"", with: "\\\""))\"}"
            }.joined(separator: ",")
            return "Transcript chunk:\n[\(manual)]\n\nClean up this transcript following the rules. Return JSON array only."
        }

        return "Transcript chunk:\n\(jsonString)\n\nClean up this transcript following the rules. Return JSON array only."
    }
}
