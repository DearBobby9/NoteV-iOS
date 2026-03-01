import Foundation

// MARK: - TranscriptPolisher

/// Orchestrates LLM-based transcript polishing.
/// Takes raw STT segments + captured frames → returns a PolishedTranscript
/// with cleaned-up text and inline images assigned by timestamp proximity.
final class TranscriptPolisher {

    private let llmService: LLMService
    private let parser: PolishedTranscriptParser
    private let settings = SettingsManager.shared

    init(llmService: LLMService = LLMService(), parser: PolishedTranscriptParser = PolishedTranscriptParser()) {
        self.llmService = llmService
        self.parser = parser
    }

    // MARK: - Polish

    /// Polish the raw transcript from a session.
    /// Returns a PolishedTranscript with cleaned text, assigned images, and bookmark markers.
    func polish(session: SessionData) async throws -> PolishedTranscript {
        let rawSegments = session.transcriptSegments
            .filter { $0.isFinal && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { $0.startTime < $1.startTime }

        guard !rawSegments.isEmpty else {
            NSLog("[TranscriptPolisher] No segments to polish — returning empty transcript")
            return PolishedTranscript(segments: [], modelUsed: settings.llmModel)
        }

        NSLog("[TranscriptPolisher] Polishing \(rawSegments.count) segments")

        // 1. Chunk segments
        let chunks = chunkSegments(rawSegments)
        NSLog("[TranscriptPolisher] Split into \(chunks.count) chunks")

        // 2. Polish each chunk via LLM
        var allPolished: [PolishedSegment] = []
        for (index, chunk) in chunks.enumerated() {
            do {
                let polished = try await polishChunk(chunk, chunkIndex: index + 1, totalChunks: chunks.count)
                allPolished.append(contentsOf: polished)
            } catch {
                NSLog("[TranscriptPolisher] Chunk \(index + 1) failed: \(error.localizedDescription) — using raw segments as fallback")
                allPolished.append(contentsOf: rawFallback(chunk))
            }
        }

        // 3. Remove overlap duplicates from chunk boundaries
        allPolished = deduplicateOverlaps(allPolished)

        // 4. Assign images to segments
        let significantFrames = selectTimelineFrames(from: session)
        allPolished = assignImages(to: allPolished, frames: significantFrames)

        // 5. Mark bookmarked segments
        allPolished = markBookmarks(in: allPolished, bookmarks: session.bookmarks)

        NSLog("[TranscriptPolisher] Complete — \(allPolished.count) polished segments, \(significantFrames.count) images assigned")

        return PolishedTranscript(
            segments: allPolished,
            modelUsed: settings.llmModel
        )
    }

    // MARK: - Chunking

    /// Split segments into chunks by time duration or segment count.
    private func chunkSegments(_ segments: [TranscriptSegment]) -> [[TranscriptSegment]] {
        let maxDuration = NoteVConfig.TranscriptPolishing.chunkDurationSeconds
        let maxSegments = NoteVConfig.TranscriptPolishing.maxSegmentsPerChunk
        let overlap = NoteVConfig.TranscriptPolishing.overlapSegments

        var chunks: [[TranscriptSegment]] = []
        var currentChunk: [TranscriptSegment] = []
        var chunkStartTime: TimeInterval = segments.first?.startTime ?? 0

        for segment in segments {
            let chunkDuration = segment.endTime - chunkStartTime
            let atLimit = currentChunk.count >= maxSegments || chunkDuration >= maxDuration

            if atLimit && !currentChunk.isEmpty {
                chunks.append(currentChunk)

                // Start next chunk with overlap for context
                let overlapStart = max(0, currentChunk.count - overlap)
                currentChunk = Array(currentChunk[overlapStart...])
                chunkStartTime = currentChunk.first?.startTime ?? segment.startTime
            }

            currentChunk.append(segment)
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks
    }

    // MARK: - LLM Call

    /// Polish a single chunk via LLM.
    private func polishChunk(_ segments: [TranscriptSegment], chunkIndex: Int, totalChunks: Int) async throws -> [PolishedSegment] {
        let userPrompt = TranscriptPolishingPromptBuilder.buildChunkPrompt(segments: segments)

        NSLog("[TranscriptPolisher] Chunk \(chunkIndex)/\(totalChunks): \(segments.count) segments, prompt: \(userPrompt.count) chars")

        let response = try await llmService.sendPrompt(
            systemPrompt: TranscriptPolishingPromptBuilder.systemPrompt,
            userPrompt: userPrompt
        )

        let polished = try parser.parse(jsonString: response)

        NSLog("[TranscriptPolisher] Chunk \(chunkIndex)/\(totalChunks): \(segments.count) raw → \(polished.count) polished segments")
        return polished
    }

    // MARK: - Fallback

    /// Convert raw segments to PolishedSegments without LLM processing.
    /// Used when polishing fails for a chunk.
    private func rawFallback(_ segments: [TranscriptSegment]) -> [PolishedSegment] {
        segments.map { seg in
            PolishedSegment(
                startTime: seg.startTime,
                endTime: seg.endTime,
                text: seg.text
            )
        }
    }

    // MARK: - Overlap Deduplication

    /// Remove segments that were duplicated due to chunk overlap.
    private func deduplicateOverlaps(_ segments: [PolishedSegment]) -> [PolishedSegment] {
        guard segments.count > 1 else { return segments }

        var result: [PolishedSegment] = [segments[0]]

        for i in 1..<segments.count {
            let current = segments[i]
            let previous = result.last!

            // Skip if this segment overlaps significantly with the previous one
            let overlapThreshold: TimeInterval = 0.5
            if current.startTime < previous.endTime - overlapThreshold
                && current.text == previous.text {
                continue
            }

            result.append(current)
        }

        return result
    }

    // MARK: - Image Assignment

    /// Select frames that should appear in the transcript timeline.
    private func selectTimelineFrames(from session: SessionData) -> [TimestampedFrame] {
        let threshold = NoteVConfig.TranscriptPolishing.imageChangeScoreThreshold
        let maxImages = NoteVConfig.TranscriptPolishing.maxImagesInTimeline

        // Include: all bookmarks + change-detected + high-score periodic frames
        let candidates = session.frames.filter { frame in
            frame.trigger == .bookmark
                || frame.trigger == .changeDetected
                || (frame.trigger == .periodic && frame.changeScore >= threshold)
        }
        .sorted { $0.timestamp < $1.timestamp }

        // Limit to max images, prioritizing bookmarks then change score
        if candidates.count <= maxImages { return candidates }

        let bookmarks = candidates.filter { $0.trigger == .bookmark }
        let others = candidates.filter { $0.trigger != .bookmark }
            .sorted { $0.changeScore > $1.changeScore }

        return Array((bookmarks + others).prefix(maxImages))
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// Assign frames to the nearest polished segment by timestamp.
    private func assignImages(to segments: [PolishedSegment], frames: [TimestampedFrame]) -> [PolishedSegment] {
        guard !frames.isEmpty, !segments.isEmpty else { return segments }

        // Build a mapping: segment index → [TimelineImage]
        var imageMap: [Int: [TimelineImage]] = [:]

        for frame in frames {
            let bestIndex = findNearestSegment(for: frame.timestamp, in: segments)
            let image = TimelineImage(
                filename: frame.imageFilename,
                timestamp: frame.timestamp,
                trigger: frame.trigger
            )
            imageMap[bestIndex, default: []].append(image)
        }

        // Rebuild segments with assigned images
        return segments.enumerated().map { index, segment in
            let images = (imageMap[index] ?? []).sorted { $0.timestamp < $1.timestamp }
            guard !images.isEmpty else { return segment }

            return PolishedSegment(
                id: segment.id,
                startTime: segment.startTime,
                endTime: segment.endTime,
                text: segment.text,
                images: images,
                isBookmarked: segment.isBookmarked
            )
        }
    }

    /// Find the segment whose time range best contains the given timestamp.
    /// Falls back to the nearest segment by start time.
    private func findNearestSegment(for timestamp: TimeInterval, in segments: [PolishedSegment]) -> Int {
        // First: look for a segment that contains the timestamp
        for (index, segment) in segments.enumerated() {
            if timestamp >= segment.startTime && timestamp <= segment.endTime {
                return index
            }
        }

        // Fallback: nearest by midpoint distance
        var bestIndex = 0
        var bestDistance = Double.infinity
        for (index, segment) in segments.enumerated() {
            let midpoint = (segment.startTime + segment.endTime) / 2
            let distance = abs(timestamp - midpoint)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    // MARK: - Bookmark Marking

    /// Mark segments that contain a bookmark timestamp.
    private func markBookmarks(in segments: [PolishedSegment], bookmarks: [Bookmark]) -> [PolishedSegment] {
        guard !bookmarks.isEmpty else { return segments }

        let bookmarkTimes = Set(bookmarks.map { $0.timestamp })

        return segments.map { segment in
            let hasBookmark = bookmarkTimes.contains { timestamp in
                timestamp >= segment.startTime - 2.0 && timestamp <= segment.endTime + 2.0
            }

            guard hasBookmark else { return segment }

            return PolishedSegment(
                id: segment.id,
                startTime: segment.startTime,
                endTime: segment.endTime,
                text: segment.text,
                images: segment.images,
                isBookmarked: true
            )
        }
    }
}
