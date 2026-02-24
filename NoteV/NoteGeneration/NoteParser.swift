import Foundation

// MARK: - NoteParser

/// Parses LLM markdown response into StructuredNotes.
/// TODO: Phase 3 — Full markdown parsing implementation
final class NoteParser {

    // MARK: - Init

    init() {
        NSLog("[NoteParser] Initialized")
    }

    // MARK: - Parsing

    /// Parse a markdown string from the LLM into StructuredNotes.
    func parse(markdown: String, modelUsed: String = NoteVConfig.NoteGeneration.llmModel) -> StructuredNotes {
        NSLog("[NoteParser] parse() called — input length: \(markdown.count) chars")

        // TODO: Phase 3
        // 1. Extract title from first # heading
        // 2. Extract summary from ## Summary section
        // 3. Extract key takeaways from ## Key Takeaways section
        // 4. Split remaining ## sections into NoteSection objects
        // 5. Parse ![image_N](description) references into NoteImage objects

        // Stub: return raw markdown as a single section
        let section = NoteSection(
            title: "Raw Notes",
            content: markdown,
            order: 0
        )

        return StructuredNotes(
            title: "Parsed Notes",
            summary: "Parsing not yet implemented.",
            sections: [section],
            keyTakeaways: [],
            modelUsed: modelUsed
        )
    }
}
