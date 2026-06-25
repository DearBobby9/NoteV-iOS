import Foundation

// MARK: - Session capture helpers

extension SessionData {

    /// Whether this session has enough material to run or export something useful.
    func hasRecoverableArtifacts(videoExistsOnDisk: Bool) -> Bool {
        !frames.isEmpty || !transcriptSegments.isEmpty || videoExistsOnDisk
    }

    /// Session content limited to a time range (for chunked note generation).
    func filtered(to timeRange: Range<TimeInterval>) -> SessionData {
        let segments = transcriptSegments.filter {
            $0.startTime >= timeRange.lowerBound && $0.startTime < timeRange.upperBound
        }
        let frames = self.frames.filter {
            $0.timestamp >= timeRange.lowerBound && $0.timestamp < timeRange.upperBound
        }
        let bookmarks = self.bookmarks.filter {
            $0.timestamp >= timeRange.lowerBound && $0.timestamp < timeRange.upperBound
        }

        var copy = self
        copy.transcriptSegments = segments
        copy.frames = frames
        copy.bookmarks = bookmarks
        copy.metadata.durationSeconds = timeRange.upperBound - timeRange.lowerBound
        copy.polishedTranscript = nil
        copy.notes = nil
        copy.todos = nil
        copy.slideAnalysis = nil
        return copy
    }
}

extension SessionStore {

    func videoExists(for sessionId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: videoURL(for: sessionId).path)
    }

    func canReprocess(_ session: SessionData) -> Bool {
        session.canReprocess(videoExistsOnDisk: videoExists(for: session.id))
    }
}
