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

        if session.metadata.durationSeconds > NoteVConfig.LongSession.extendedDurationThreshold {
            return try await generateNotesInChunks(from: session)
        }

        return try await generateNotesSinglePass(from: session)
    }

    // MARK: - Single pass

    private func generateNotesSinglePass(from session: SessionData) async throws -> StructuredNotes {
        let selectedFrames = session.topFrames()
        NSLog("[NoteGenerator] Selected \(selectedFrames.count) top frames for prompt")

        let (userPrompt, images, includedFrames) = promptBuilder.buildPrompt(
            session: session,
            selectedFrames: selectedFrames
        )
        NSLog("[NoteGenerator] Prompt built — \(userPrompt.count) chars, \(images.count) images")

        let response = try await llmService.sendPrompt(
            systemPrompt: PromptBuilder.systemPrompt,
            userPrompt: userPrompt,
            images: images
        )
        NSLog("[NoteGenerator] LLM response received — \(response.count) chars")

        return try parseAndEnrich(
            response: response,
            includedFrames: includedFrames
        )
    }

    // MARK: - Chunked (long sessions)

    private func generateNotesInChunks(from session: SessionData) async throws -> StructuredNotes {
        let chunkDuration = NoteVConfig.LongSession.noteChunkDurationSeconds
        let duration = max(session.metadata.durationSeconds, 1)
        var mergedTitle = "Lecture Notes"
        var mergedSummary = ""
        var mergedTakeaways: [String] = []
        var mergedSections: [NoteSection] = []
        var sectionOrder = 0
        var chunkErrors: [String] = []

        var chunkStart: TimeInterval = 0
        var chunkIndex = 0
        while chunkStart < duration {
            let chunkEnd = min(chunkStart + chunkDuration, duration)
            let chunkSession = session.filtered(to: chunkStart..<chunkEnd)
            let selectedFrames = chunkSession.topFrames()

            do {
                let (userPrompt, images, includedFrames) = promptBuilder.buildPrompt(
                    session: chunkSession,
                    selectedFrames: selectedFrames,
                    chunkLabel: "Part \(chunkIndex + 1)"
                )

                let response = try await llmService.sendPrompt(
                    systemPrompt: PromptBuilder.systemPrompt,
                    userPrompt: userPrompt,
                    images: images
                )

                let chunkNotes = try parseAndEnrich(
                    response: response,
                    includedFrames: includedFrames
                )

                if chunkIndex == 0 {
                    mergedTitle = chunkNotes.title
                    mergedSummary = chunkNotes.summary
                } else if !chunkNotes.summary.isEmpty {
                    mergedSummary += mergedSummary.isEmpty ? chunkNotes.summary : " " + chunkNotes.summary
                }

                for takeaway in chunkNotes.keyTakeaways where !mergedTakeaways.contains(takeaway) {
                    mergedTakeaways.append(takeaway)
                }

                for section in chunkNotes.sections.sorted(by: { $0.order < $1.order }) {
                    mergedSections.append(
                        NoteSection(
                            id: section.id,
                            title: section.title,
                            content: section.content,
                            images: section.images,
                            order: sectionOrder,
                            startTime: section.startTime,
                            endTime: section.endTime,
                            isBookmarkSection: section.isBookmarkSection
                        )
                    )
                    sectionOrder += 1
                }
            } catch {
                chunkErrors.append("Part \(chunkIndex + 1): \(error.localizedDescription)")
                NSLog("[NoteGenerator] Chunk \(chunkIndex + 1) failed: \(error.localizedDescription)")
            }

            chunkStart = chunkEnd
            chunkIndex += 1
        }

        guard !mergedSections.isEmpty else {
            if let firstError = chunkErrors.first {
                throw NSError(
                    domain: "NoteGenerator",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: firstError]
                )
            }
            throw NSError(
                domain: "NoteGenerator",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "No notes generated from any chunk"]
            )
        }

        if !chunkErrors.isEmpty {
            NSLog("[NoteGenerator] Chunked notes partial — \(chunkErrors.count) chunk failures")
        }

        let notes = StructuredNotes(
            title: mergedTitle,
            summary: mergedSummary,
            sections: mergedSections,
            keyTakeaways: mergedTakeaways,
            modelUsed: SettingsManager.shared.llmModel
        )
        NSLog("[NoteGenerator] Chunked notes merged — \(chunkIndex) chunks, \(mergedSections.count) sections")
        return notes
    }

    private func parseAndEnrich(
        response: String,
        includedFrames: [TimestampedFrame]
    ) throws -> StructuredNotes {
        var imageMap: [Int: String] = [:]
        for (index, frame) in includedFrames.enumerated() {
            imageMap[index + 1] = frame.imageFilename
        }

        let notes = noteParser.parse(
            markdown: response,
            imageFilenameMap: imageMap,
            modelUsed: SettingsManager.shared.llmModel
        )
        return enrichImageTimestamps(notes, includedFrames: includedFrames)
    }

    // MARK: - Helpers

    /// Backfill NoteImage.timestamp from actual frame capture times.
    private func enrichImageTimestamps(_ notes: StructuredNotes, includedFrames: [TimestampedFrame]) -> StructuredNotes {
        let timestampLookup: [String: TimeInterval] = Dictionary(
            uniqueKeysWithValues: includedFrames.map { ($0.imageFilename, $0.timestamp) }
        )

        let enrichedSections = notes.sections.map { section in
            let enrichedImages = section.images.map { image in
                NoteImage(
                    id: image.id,
                    filename: image.filename,
                    caption: image.caption,
                    timestamp: timestampLookup[image.filename] ?? image.timestamp
                )
            }
            return NoteSection(
                id: section.id,
                title: section.title,
                content: section.content,
                images: enrichedImages,
                order: section.order,
                startTime: section.startTime,
                endTime: section.endTime,
                isBookmarkSection: section.isBookmarkSection
            )
        }

        return StructuredNotes(
            id: notes.id,
            title: notes.title,
            summary: notes.summary,
            sections: enrichedSections,
            keyTakeaways: notes.keyTakeaways,
            generatedAt: notes.generatedAt,
            modelUsed: notes.modelUsed
        )
    }
}
