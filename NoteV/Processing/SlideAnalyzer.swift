import Foundation

// MARK: - SlideAnalyzer

/// Analyzes captured frames to extract slide content using LLM Vision.
/// Pipeline: FrameDeduplicator → LLM Vision per unique slide → SlideAnalysisResult.
final class SlideAnalyzer {

    private let deduplicator = FrameDeduplicator()
    private let imageStore: ImageStore
    private let llmService: LLMService

    init(imageStore: ImageStore = ImageStore(), llmService: LLMService = LLMService()) {
        self.imageStore = imageStore
        self.llmService = llmService
    }

    // MARK: - Analyze

    /// Analyze a session's frames: deduplicate → extract text from unique slides via LLM Vision.
    func analyze(session: SessionData) async throws -> SlideAnalysisResult {
        let sessionId = session.id
        NSLog("[SlideAnalyzer] Starting analysis for session \(sessionId) — \(session.frames.count) frames")

        // Step 1: Deduplicate frames
        var uniqueSlides = deduplicator.deduplicate(
            frames: session.frames,
            imageStore: imageStore,
            sessionId: sessionId
        )

        let totalFrames = session.frames.count
        let duplicatesRemoved = totalFrames - uniqueSlides.count

        guard !uniqueSlides.isEmpty else {
            NSLog("[SlideAnalyzer] No unique slides found after deduplication")
            return SlideAnalysisResult(
                uniqueSlides: [],
                totalFramesProcessed: totalFrames,
                duplicatesRemoved: duplicatesRemoved
            )
        }

        // Step 2: Extract text from each unique slide via LLM Vision (concurrency limit of 3)
        let concurrencyLimit = 3
        var processedSlides: [UniqueSlide] = []

        for chunk in uniqueSlides.chunked(into: concurrencyLimit) {
            let results = await withTaskGroup(of: (Int, String?).self) { group in
                for slide in chunk {
                    group.addTask {
                        let text = await self.extractSlideText(
                            filename: slide.representativeFrame,
                            sessionId: sessionId
                        )
                        return (slide.slideNumber, text)
                    }
                }

                var mapping: [Int: String?] = [:]
                for await (number, text) in group {
                    mapping[number] = text
                }
                return mapping
            }

            for slide in chunk {
                var updated = slide
                if let text = results[slide.slideNumber] {
                    updated = UniqueSlide(
                        representativeFrame: slide.representativeFrame,
                        timestamp: slide.timestamp,
                        slideNumber: slide.slideNumber,
                        extractedText: text,
                        duplicateCount: slide.duplicateCount
                    )
                }
                processedSlides.append(updated)
            }
        }

        let result = SlideAnalysisResult(
            uniqueSlides: processedSlides,
            totalFramesProcessed: totalFrames,
            duplicatesRemoved: duplicatesRemoved
        )

        let extractedCount = processedSlides.filter { $0.extractedText != nil }.count
        NSLog("[SlideAnalyzer] Analysis complete — \(processedSlides.count) unique slides, \(extractedCount) with extracted text, \(duplicatesRemoved) duplicates removed")

        return result
    }

    // MARK: - Extract Text

    private func extractSlideText(filename: String, sessionId: UUID) async -> String? {
        guard let imageData = imageStore.loadImage(filename: filename, sessionId: sessionId) else {
            NSLog("[SlideAnalyzer] Could not load image: \(filename)")
            return nil
        }

        let systemPrompt = "You are a slide text extraction assistant."
        let userPrompt = """
        Extract all text and structural elements from this slide image.
        Include: title, bullet points, formulas, diagram labels, table content.
        Return plain text only, preserving the logical structure with line breaks.
        If the image is not a slide (e.g., person, classroom), respond with "NOT_A_SLIDE".
        """

        do {
            let response = try await llmService.sendPrompt(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                images: [imageData]
            )

            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "NOT_A_SLIDE" || trimmed.isEmpty {
                return nil
            }
            return trimmed
        } catch {
            NSLog("[SlideAnalyzer] LLM extraction failed for \(filename): \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Array Extension

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
