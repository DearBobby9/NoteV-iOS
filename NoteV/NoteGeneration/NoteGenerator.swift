import Foundation

// MARK: - NoteGenerator

/// Orchestrates note generation: selects frames, builds prompt, calls LLM, parses result.
/// TODO: Phase 3 — Full LLM integration
final class NoteGenerator {

    // MARK: - Properties

    private let promptBuilder: PromptBuilder
    private let llmService: LLMService
    private let noteParser: NoteParser

    // MARK: - Init

    init(
        promptBuilder: PromptBuilder = PromptBuilder(),
        llmService: LLMService = LLMService(),
        noteParser: NoteParser = NoteParser()
    ) {
        self.promptBuilder = promptBuilder
        self.llmService = llmService
        self.noteParser = noteParser
        NSLog("[NoteGenerator] Initialized — provider: \(NoteVConfig.NoteGeneration.llmProvider.rawValue), model: \(NoteVConfig.NoteGeneration.llmModel)")
    }

    // MARK: - Generation

    /// Generate structured notes from a completed session.
    func generateNotes(from session: SessionData) async throws -> StructuredNotes {
        NSLog("[NoteGenerator] generateNotes() called — \(session.frames.count) frames, \(session.transcriptSegments.count) segments")

        // TODO: Phase 3
        // 1. Select top frames via session.topFrames()
        // 2. Build multimodal prompt via PromptBuilder
        // 3. Send to LLM via LLMService
        // 4. Parse response via NoteParser
        // 5. Return StructuredNotes

        // Stub: return empty notes
        let notes = StructuredNotes(
            title: session.metadata.title,
            summary: "Notes generation not yet implemented.",
            sections: [],
            keyTakeaways: []
        )

        NSLog("[NoteGenerator] Generated stub notes for session: \(session.id)")
        return notes
    }
}
