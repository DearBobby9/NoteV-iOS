import Foundation

// MARK: - BookmarkDetector

/// Detects bookmarks by monitoring transcript segments for the keyword "mark".
/// Simplified architecture: no separate SFSpeechRecognizer — just watches AudioPipeline output.
final class BookmarkDetector {

    // MARK: - Properties

    private var bookmarkContinuation: AsyncStream<Bookmark>.Continuation?
    private var lastBookmarkTime: TimeInterval = -999
    private var bookmarkCount = 0
    private var isMonitoring = false

    // Transcript history for context capture
    private var recentSegments: [TranscriptSegment] = []

    lazy var bookmarkStream: AsyncStream<Bookmark> = {
        AsyncStream { continuation in
            self.bookmarkContinuation = continuation
        }
    }()

    // MARK: - Init

    init() {
        NSLog("[BookmarkDetector] Initialized — keyword: \"\(NoteVConfig.Bookmark.keyword)\", cooldown: \(NoteVConfig.Bookmark.cooldownSeconds)s")
    }

    // MARK: - Monitoring

    /// Monitor transcript segments for bookmark keyword.
    func monitor(transcriptStream: AsyncStream<TranscriptSegment>) async {
        NSLog("[BookmarkDetector] monitor() started — listening for \"\(NoteVConfig.Bookmark.keyword)\"")
        isMonitoring = true

        for await segment in transcriptStream {
            guard isMonitoring else { break }

            // Track recent segments for context
            recentSegments.append(segment)
            pruneOldSegments(currentTime: segment.endTime)

            // [P2 fix] Only check final segments to avoid interim duplicates
            guard segment.isFinal else { continue }

            // Check for keyword in this segment
            if containsKeyword(segment.text) && isCooldownExpired(currentTime: segment.endTime) {
                lastBookmarkTime = segment.endTime
                bookmarkCount += 1

                // Build surrounding transcript context
                let context = recentSegments
                    .map { $0.text }
                    .joined(separator: " ")

                let bookmark = Bookmark(
                    timestamp: segment.endTime,
                    surroundingTranscript: context
                )

                bookmarkContinuation?.yield(bookmark)
                NSLog("[BookmarkDetector] Bookmark #\(bookmarkCount) triggered at \(String(format: "%.1f", segment.endTime))s — context: \"\(context.prefix(80))...\"")
            }
        }

        NSLog("[BookmarkDetector] Monitoring loop ended — \(bookmarkCount) bookmarks detected")
    }

    /// Stop detection.
    func stop() {
        NSLog("[BookmarkDetector] stop() called")
        isMonitoring = false
        bookmarkContinuation?.finish()
        recentSegments = []
    }

    // MARK: - Keyword Check

    /// [P2 fix] Check if the given text contains the bookmark keyword using word boundary matching.
    /// Prevents false positives from "remark", "market", "trademark" etc.
    func containsKeyword(_ text: String) -> Bool {
        let keyword = NSRegularExpression.escapedPattern(for: NoteVConfig.Bookmark.keyword.lowercased())
        let pattern = "\\b\(keyword)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            // Fallback to simple contains if regex fails
            return text.lowercased().contains(NoteVConfig.Bookmark.keyword.lowercased())
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    /// Whether enough time has passed since the last bookmark.
    func isCooldownExpired(currentTime: TimeInterval) -> Bool {
        (currentTime - lastBookmarkTime) >= NoteVConfig.Bookmark.cooldownSeconds
    }

    // MARK: - Helpers

    /// Remove segments older than the context window.
    private func pruneOldSegments(currentTime: TimeInterval) {
        let cutoff = currentTime - NoteVConfig.Bookmark.transcriptContextWindow
        recentSegments.removeAll { $0.endTime < cutoff }
    }
}
