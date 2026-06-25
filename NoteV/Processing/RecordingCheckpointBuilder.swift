import Foundation

// MARK: - RecordingCheckpointBuilder

/// Builds partial `SessionData` snapshots persisted during active recording.
enum RecordingCheckpointBuilder {

    static func makeSessionData(
        sessionId: UUID,
        sessionStartTime: Date,
        duration: TimeInterval,
        captureSource: CaptureSource,
        frames: [TimestampedFrame],
        transcriptSegments: [TranscriptSegment],
        bookmarks: [Bookmark],
        existingCourse: SessionData?
    ) -> SessionData {
        let metadata = SessionMetadata(
            sessionId: sessionId,
            startDate: sessionStartTime,
            endDate: nil,
            captureSource: captureSource,
            title: "Recording in progress",
            durationSeconds: duration,
            videoFilename: nil
        )

        let framesWithoutImageData = frames.map { frame -> TimestampedFrame in
            var copy = frame
            copy.imageData = nil
            return copy
        }

        return SessionData(
            metadata: metadata,
            frames: framesWithoutImageData,
            transcriptSegments: transcriptSegments,
            bookmarks: bookmarks,
            polishedTranscript: nil,
            notes: nil,
            todos: nil,
            slideAnalysis: nil,
            courseId: existingCourse?.courseId,
            courseName: existingCourse?.courseName
        )
    }
}
