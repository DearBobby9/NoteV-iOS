import Foundation

// MARK: - NoteGenerator

/// Orchestrates note generation: selects frames, builds prompt, calls LLM, parses result.
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
        let settings = SettingsManager.shared
        NSLog("[NoteGenerator] Initialized — provider: \(settings.llmProvider.rawValue), model: \(settings.llmModel)")
    }

    // MARK: - Generation

    /// Generate structured notes from a completed session.
    func generateNotes(from session: SessionData) async throws -> StructuredNotes {
        NSLog("[NoteGenerator] generateNotes() called — \(session.frames.count) frames, \(session.transcriptSegments.count) segments")

        // 1. Select top frames (bookmarks first, then highest change score)
        let selectedFrames = session.topFrames()
        NSLog("[NoteGenerator] Selected \(selectedFrames.count) top frames for prompt")

        // 2. Build multimodal prompt — returns only frames whose images loaded successfully
        let (userPrompt, images, includedFrames) = promptBuilder.buildPrompt(session: session, selectedFrames: selectedFrames)
        NSLog("[NoteGenerator] Prompt built — \(userPrompt.count) chars, \(images.count) images")

        // 3. Send to LLM
        let response = try await llmService.sendPrompt(
            systemPrompt: PromptBuilder.systemPrompt,
            userPrompt: userPrompt,
            images: images
        )
        NSLog("[NoteGenerator] LLM response received — \(response.count) chars")

        // 4. Build image_N → filename mapping from includedFrames (matches prompt indices exactly)
        var imageMap: [Int: String] = [:]
        for (index, frame) in includedFrames.enumerated() {
            imageMap[index + 1] = frame.imageFilename
        }
        NSLog("[NoteGenerator] Image mapping built — \(imageMap.count) entries")

        // 5. Parse response into StructuredNotes (pass mapping directly — no mutable state)
        let notes = noteParser.parse(markdown: response, imageFilenameMap: imageMap, modelUsed: SettingsManager.shared.llmModel)
        NSLog("[NoteGenerator] Notes parsed — \"\(notes.title)\", \(notes.sections.count) sections")

        return notes
    }
}
