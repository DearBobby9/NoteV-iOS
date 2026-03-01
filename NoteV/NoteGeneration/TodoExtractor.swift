import Foundation

// MARK: - TodoExtractError

enum TodoExtractError: LocalizedError {
    case noTranscript
    case llmFailed(String)

    var errorDescription: String? {
        switch self {
        case .noTranscript:
            return "No transcript available for TODO extraction"
        case .llmFailed(let detail):
            return "LLM TODO extraction failed: \(detail)"
        }
    }
}

// MARK: - TodoExtractor

/// Orchestrates LLM-based action item extraction from lecture transcripts.
/// Pattern mirrors TranscriptPolisher — final class, dependency injection, async throws.
final class TodoExtractor {

    private let llmService: LLMService
    private let parser: TodoParser
    private let settings = SettingsManager.shared

    init(llmService: LLMService = LLMService(), parser: TodoParser = TodoParser()) {
        self.llmService = llmService
        self.parser = parser
        NSLog("[TodoExtractor] Initialized — provider: \(settings.llmProvider.rawValue), model: \(settings.llmModel)")
    }

    // MARK: - Extract

    /// Extract action items from a session's transcript.
    /// Uses polished transcript if available, falls back to raw transcript.
    func extract(from session: SessionData) async throws -> [TodoItem] {
        // Verify we have transcript content
        let hasPolished = session.polishedTranscript != nil && !(session.polishedTranscript?.segments.isEmpty ?? true)
        let hasRaw = !session.transcriptSegments.filter({ $0.isFinal }).isEmpty

        guard hasPolished || hasRaw else {
            NSLog("[TodoExtractor] No transcript available — skipping extraction")
            throw TodoExtractError.noTranscript
        }

        NSLog("[TodoExtractor] Extracting TODOs — source: \(hasPolished ? "polished" : "raw") transcript")

        // Build prompt (text-only, no images needed)
        let userPrompt = TodoExtractionPromptBuilder.buildPrompt(session: session)
        NSLog("[TodoExtractor] Prompt built — \(userPrompt.count) chars")

        // Call LLM (text-only — no images parameter)
        let response: String
        do {
            response = try await llmService.sendPrompt(
                systemPrompt: TodoExtractionPromptBuilder.systemPrompt,
                userPrompt: userPrompt
            )
        } catch {
            NSLog("[TodoExtractor] LLM call failed: \(error.localizedDescription)")
            throw TodoExtractError.llmFailed(error.localizedDescription)
        }

        NSLog("[TodoExtractor] LLM response received — \(response.count) chars")

        // Parse JSON response into TodoItems
        let items = try parser.parse(jsonString: response, sessionDate: session.metadata.startDate)
        NSLog("[TodoExtractor] Extraction complete — \(items.count) action items found")

        return items
    }
}
