import Foundation

// MARK: - PromptBuilder

/// Builds the multimodal prompt for note generation.
/// Combines transcript, selected frames, and bookmarks into a structured LLM prompt.
/// TODO: Phase 3 — Full prompt construction with image encoding
final class PromptBuilder {

    // MARK: - Init

    init() {
        NSLog("[PromptBuilder] Initialized")
    }

    // MARK: - Prompt Template

    static let systemPrompt = """
    You are an expert academic note-taker. You receive a lecture transcript and captured \
    images from the lecture (slides, whiteboard, diagrams). Your job is to produce \
    comprehensive, well-structured notes that integrate both the spoken content and \
    visual materials.

    Output format:
    # [Lecture Title]

    ## Summary
    [2-3 sentence overview]

    ## Key Takeaways
    - [takeaway 1]
    - [takeaway 2]
    ...

    ## [Section Title]
    [Content with references to images where relevant]
    ![image_N](description of what the image shows)

    ...

    Guidelines:
    - Integrate visual content naturally with spoken content
    - Note when a slide or diagram illustrates a concept from the lecture
    - Use markdown formatting for structure
    - Include key definitions, formulas, and examples
    - Mark bookmarked moments as important highlights
    """

    // MARK: - Building

    /// Build the full prompt from session data.
    func buildPrompt(session: SessionData, selectedFrames: [TimestampedFrame]) -> String {
        NSLog("[PromptBuilder] buildPrompt() called — \(selectedFrames.count) frames")

        // TODO: Phase 3
        // 1. Format transcript with timestamps
        // 2. Encode selected frames as base64 for multimodal API
        // 3. Mark bookmarked sections
        // 4. Assemble full prompt with system prompt + user content

        var prompt = "TRANSCRIPT:\n"
        prompt += session.fullTranscript
        prompt += "\n\nCAPTURED IMAGES: \(selectedFrames.count) frames attached"
        prompt += "\n\nBOOKMARKS: \(session.bookmarks.count) moments marked as important"

        return prompt
    }
}
