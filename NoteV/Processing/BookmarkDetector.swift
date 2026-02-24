import Foundation
import Speech

// MARK: - BookmarkDetector

/// Detects voice-triggered bookmarks using Apple Speech on-device recognition.
/// Listens for the keyword (default: "mark") and fires bookmark events.
/// TODO: Phase 2 — SFSpeechRecognizer keyword spotting implementation
final class BookmarkDetector {

    // MARK: - Properties

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionTask: SFSpeechRecognitionTask?
    private var bookmarkContinuation: AsyncStream<Bookmark>.Continuation?
    private var lastBookmarkTime: TimeInterval = -999

    lazy var bookmarkStream: AsyncStream<Bookmark> = {
        AsyncStream { continuation in
            self.bookmarkContinuation = continuation
        }
    }()

    // MARK: - Init

    init() {
        NSLog("[BookmarkDetector] Initialized — keyword: \"\(NoteVConfig.Bookmark.keyword)\", cooldown: \(NoteVConfig.Bookmark.cooldownSeconds)s")
    }

    // MARK: - Detection

    /// Start listening for bookmark keywords.
    func startDetection() async {
        NSLog("[BookmarkDetector] startDetection() called")
        // TODO: Phase 2
        // 1. Request SFSpeechRecognizer authorization
        // 2. Create SFSpeechAudioBufferRecognitionRequest
        // 3. Start recognitionTask
        // 4. Monitor results for keyword match
        // 5. Apply cooldown between triggers
        // 6. On match: capture photo + surrounding transcript → Bookmark
    }

    /// Stop detection.
    func stop() {
        NSLog("[BookmarkDetector] stop() called")
        recognitionTask?.cancel()
        recognitionTask = nil
        bookmarkContinuation?.finish()
    }

    // MARK: - Keyword Check

    /// Check if the given text contains the bookmark keyword.
    func containsKeyword(_ text: String) -> Bool {
        text.lowercased().contains(NoteVConfig.Bookmark.keyword.lowercased())
    }

    /// Whether enough time has passed since the last bookmark.
    func isCooldownExpired(currentTime: TimeInterval) -> Bool {
        (currentTime - lastBookmarkTime) >= NoteVConfig.Bookmark.cooldownSeconds
    }
}
