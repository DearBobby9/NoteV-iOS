import Foundation

// MARK: - PromptBuilder

/// Builds the multimodal prompt for note generation.
/// Combines transcript, selected frames, and bookmarks into a structured LLM prompt.
final class PromptBuilder {

    // MARK: - Properties

    private let imageStore: ImageStore

    // MARK: - Init

    init(imageStore: ImageStore = ImageStore()) {
        self.imageStore = imageStore
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

    ## [Section Title] [MM:SS-MM:SS]
    [Content with references to images where relevant]
    ![image_N](description of what the image shows)

    ## [BOOKMARK] Bookmarked Highlights [MM:SS-MM:SS]
    [Important moments the student bookmarked]

    ...

    Guidelines:
    - Include a timestamp range [MM:SS-MM:SS] after each section title, indicating the \
    approximate start and end time of the lecture content covered in that section
    - For bookmarked highlight sections, prefix the title with [BOOKMARK] \
    (e.g., "## [BOOKMARK] Important Moment [05:30-06:15]")
    - Integrate visual content naturally with spoken content
    - Note when a slide or diagram illustrates a concept from the lecture
    - Use markdown formatting for structure
    - Include key definitions, formulas, and examples
    - Mark bookmarked moments as important highlights
    - Reference images using the format ![image_N](caption) where N is the image index
    """

    // MARK: - Building

    /// Build the full prompt from session data. Returns (prompt text, image data array, frames actually included).
    /// Only frames whose images load successfully are included — this keeps image_N indices
    /// aligned with the actual image data sent to the LLM.
    func buildPrompt(session: SessionData, selectedFrames: [TimestampedFrame]) -> (String, [Data], [TimestampedFrame]) {
        NSLog("[PromptBuilder] buildPrompt() called — \(selectedFrames.count) frames, \(session.transcriptSegments.count) segments")

        var prompt = ""
        var images: [Data] = []
        var includedFrames: [TimestampedFrame] = []

        // 1. Format transcript with timestamps
        prompt += "## TRANSCRIPT\n\n"
        let sortedSegments = session.transcriptSegments.sorted { $0.startTime < $1.startTime }

        if sortedSegments.isEmpty {
            prompt += "(No transcript available)\n"
        } else {
            for segment in sortedSegments {
                let timestamp = formatTimestamp(segment.startTime)
                prompt += "[\(timestamp)] \(segment.text)\n"
            }
        }

        // 2. Pre-filter to only frames whose images load successfully
        let loadable: [(TimestampedFrame, Data)] = selectedFrames.compactMap { frame in
            guard let data = imageStore.loadImage(filename: frame.imageFilename, sessionId: session.id) else {
                NSLog("[PromptBuilder] Skipping frame \(frame.imageFilename) — image not found on disk")
                return nil
            }
            return (frame, data)
        }

        // 3. List captured images with metadata — only loadable frames
        prompt += "\n## CAPTURED IMAGES\n\n"
        prompt += "\(loadable.count) images captured during the lecture:\n\n"

        for (index, (frame, imageData)) in loadable.enumerated() {
            let timestamp = formatTimestamp(frame.timestamp)
            let triggerLabel: String
            switch frame.trigger {
            case .periodic: triggerLabel = "periodic sample"
            case .changeDetected: triggerLabel = "slide/content change detected"
            case .bookmark: triggerLabel = "bookmarked moment"
            }

            prompt += "- image_\(index + 1): captured at [\(timestamp)] (\(triggerLabel), change score: \(String(format: "%.2f", frame.changeScore)))\n"
            images.append(imageData)
            includedFrames.append(frame)
        }

        // 3. Mark bookmarked moments
        if !session.bookmarks.isEmpty {
            prompt += "\n## BOOKMARKED MOMENTS (marked as important by the student)\n\n"
            for (index, bookmark) in session.bookmarks.enumerated() {
                let timestamp = formatTimestamp(bookmark.timestamp)
                prompt += "- Bookmark \(index + 1) at [\(timestamp)]: \"\(bookmark.surroundingTranscript.prefix(200))\"\n"
            }
        }

        prompt += "\n## INSTRUCTIONS\n\n"
        prompt += "Please generate comprehensive, well-structured notes from this lecture. "
        prompt += "Integrate the visual content (slides, diagrams) with the spoken transcript. "
        prompt += "Pay special attention to bookmarked moments as the student marked these as important. "
        prompt += "If there are bookmarked moments, create a dedicated '## Bookmarked Highlights' section summarizing each bookmarked moment with its timestamp and importance. "
        prompt += "Reference the captured images using ![image_N](description) format.\n"

        NSLog("[PromptBuilder] Prompt built — \(prompt.count) chars, \(images.count) images (\(selectedFrames.count - includedFrames.count) skipped)")
        return (prompt, images, includedFrames)
    }

    // MARK: - Helpers

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
    }
}
