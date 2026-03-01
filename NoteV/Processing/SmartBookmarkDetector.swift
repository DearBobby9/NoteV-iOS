import Foundation

// MARK: - SmartBookmarkResult

struct SmartBookmarkResult: Sendable {
    let confidence: Double
    let triggerPhrase: String
    let tier: Int
    let label: String
}

// MARK: - SmartBookmarkDetector

/// Deterministic phrase matching for auto-detecting important lecture moments.
/// Uses a 4-tier keyword taxonomy based on academic corpus research.
/// Synchronous — designed for inline detection in SessionRecorder transcript collector.
final class SmartBookmarkDetector {

    // MARK: - Keyword Taxonomy

    private struct Keyword: Sendable {
        let phrase: String
        let tier: Int
        let baseScore: Double
        let label: String
    }

    private let keywords: [Keyword] = [
        // Tier 1 (0.95): Exam/assignment/deadline phrases
        Keyword(phrase: "will be on the exam", tier: 1, baseScore: 0.95, label: "Exam Content"),
        Keyword(phrase: "on the exam", tier: 1, baseScore: 0.95, label: "Exam Content"),
        Keyword(phrase: "on the final", tier: 1, baseScore: 0.95, label: "Exam Content"),
        Keyword(phrase: "on the midterm", tier: 1, baseScore: 0.95, label: "Exam Content"),
        Keyword(phrase: "on the test", tier: 1, baseScore: 0.95, label: "Exam Content"),
        Keyword(phrase: "assignment due", tier: 1, baseScore: 0.95, label: "Deadline"),
        Keyword(phrase: "homework due", tier: 1, baseScore: 0.95, label: "Deadline"),
        Keyword(phrase: "submit by", tier: 1, baseScore: 0.95, label: "Deadline"),
        Keyword(phrase: "due by", tier: 1, baseScore: 0.95, label: "Deadline"),
        Keyword(phrase: "due date", tier: 1, baseScore: 0.95, label: "Deadline"),
        Keyword(phrase: "due next", tier: 1, baseScore: 0.95, label: "Deadline"),
        Keyword(phrase: "turn in", tier: 1, baseScore: 0.90, label: "Deadline"),
        Keyword(phrase: "test on", tier: 1, baseScore: 0.95, label: "Exam Content"),
        Keyword(phrase: "quiz on", tier: 1, baseScore: 0.90, label: "Quiz"),
        Keyword(phrase: "final exam", tier: 1, baseScore: 0.95, label: "Exam"),
        Keyword(phrase: "midterm", tier: 1, baseScore: 0.90, label: "Exam"),

        // Tier 2 (0.80): Importance markers
        Keyword(phrase: "this is important", tier: 2, baseScore: 0.80, label: "Important"),
        Keyword(phrase: "very important", tier: 2, baseScore: 0.80, label: "Important"),
        Keyword(phrase: "really important", tier: 2, baseScore: 0.80, label: "Important"),
        Keyword(phrase: "key concept", tier: 2, baseScore: 0.80, label: "Key Concept"),
        Keyword(phrase: "key point", tier: 2, baseScore: 0.80, label: "Key Point"),
        Keyword(phrase: "make sure you", tier: 2, baseScore: 0.75, label: "Important"),
        Keyword(phrase: "don't forget", tier: 2, baseScore: 0.75, label: "Important"),
        Keyword(phrase: "do not forget", tier: 2, baseScore: 0.75, label: "Important"),
        Keyword(phrase: "pay attention", tier: 2, baseScore: 0.80, label: "Important"),
        Keyword(phrase: "pay close attention", tier: 2, baseScore: 0.85, label: "Important"),
        Keyword(phrase: "you need to know", tier: 2, baseScore: 0.80, label: "Important"),
        Keyword(phrase: "you should know", tier: 2, baseScore: 0.75, label: "Important"),
        Keyword(phrase: "must know", tier: 2, baseScore: 0.80, label: "Important"),
        Keyword(phrase: "write this down", tier: 2, baseScore: 0.85, label: "Important"),

        // Tier 3 (0.60): Structural/summary markers
        Keyword(phrase: "to summarize", tier: 3, baseScore: 0.60, label: "Summary"),
        Keyword(phrase: "in summary", tier: 3, baseScore: 0.60, label: "Summary"),
        Keyword(phrase: "in conclusion", tier: 3, baseScore: 0.60, label: "Summary"),
        Keyword(phrase: "the main point", tier: 3, baseScore: 0.60, label: "Key Point"),
        Keyword(phrase: "the takeaway", tier: 3, baseScore: 0.60, label: "Takeaway"),
        Keyword(phrase: "remember that", tier: 3, baseScore: 0.60, label: "Important"),
        Keyword(phrase: "let me repeat", tier: 3, baseScore: 0.65, label: "Emphasis"),
        Keyword(phrase: "i'll say that again", tier: 3, baseScore: 0.65, label: "Emphasis"),
        Keyword(phrase: "the formula is", tier: 3, baseScore: 0.60, label: "Formula"),

        // Tier 4 (0.35): Weak signals — boost only, never trigger alone
        Keyword(phrase: "note that", tier: 4, baseScore: 0.35, label: "Note"),
        Keyword(phrase: "keep in mind", tier: 4, baseScore: 0.35, label: "Note"),
        Keyword(phrase: "worth mentioning", tier: 4, baseScore: 0.35, label: "Note"),
        Keyword(phrase: "interesting", tier: 4, baseScore: 0.30, label: "Note"),
    ]

    // Negation prefixes that suppress detection
    private let negationPhrases: [String] = [
        "won't be", "will not be", "not going to be", "not important",
        "don't need to", "not on the", "isn't important", "is not important"
    ]

    // Per-tier cooldowns (seconds)
    private let tierCooldowns: [Int: TimeInterval] = [
        1: 15.0,
        2: 20.0,
        3: 60.0,
        4: 60.0,
    ]

    // Mutable state (not truly Sendable but used single-threaded on MainActor)
    private var lastTriggerTime: TimeInterval = -100
    private var lastTierTriggerTimes: [Int: TimeInterval] = [:]

    // MARK: - Detection

    /// Detect if text contains a smart bookmark trigger.
    /// `sessionTime` is seconds since session start for cooldown tracking.
    /// Returns nil if no trigger detected or cooldown active.
    func detect(text: String, fullBuffer: String, sessionTime: TimeInterval) -> SmartBookmarkResult? {
        let lowText = text.lowercased()
        let lowBuffer = fullBuffer.lowercased()

        // Global cooldown
        guard sessionTime - lastTriggerTime >= NoteVConfig.SmartBookmark.globalCooldownSeconds else {
            return nil
        }

        // Check for negation in the surrounding buffer
        let hasNegation = negationPhrases.contains { lowBuffer.contains($0) }

        // Check if text is a question (ends with ?)
        let isQuestion = text.trimmingCharacters(in: .whitespaces).hasSuffix("?")

        // Find best matching keyword
        var bestMatch: (keyword: Keyword, score: Double)?

        for keyword in keywords {
            guard lowBuffer.contains(keyword.phrase) || lowText.contains(keyword.phrase) else {
                continue
            }

            // Tier 4 never triggers alone
            if keyword.tier == 4 { continue }

            var score = keyword.baseScore

            // Modifiers
            if hasNegation { score -= 0.20 }
            if isQuestion { score -= 0.10 }

            // Date boost: buffer contains day/date references
            if containsDateReference(lowBuffer) { score += 0.10 }

            // Number boost: buffer contains numbers
            if containsNumber(lowBuffer) { score += 0.10 }

            // Co-occurrence boost: multiple keywords detected
            let otherMatches = keywords.filter { $0.phrase != keyword.phrase && lowBuffer.contains($0.phrase) }
            if !otherMatches.isEmpty { score += 0.10 }

            // Clamp
            score = min(1.0, max(0.0, score))

            guard score >= NoteVConfig.SmartBookmark.confidenceThreshold else { continue }

            // Per-tier cooldown
            if let lastTier = lastTierTriggerTimes[keyword.tier],
               sessionTime - lastTier < (tierCooldowns[keyword.tier] ?? 20.0) {
                continue
            }

            if bestMatch == nil || score > bestMatch!.score {
                bestMatch = (keyword, score)
            }
        }

        guard let match = bestMatch else { return nil }

        // Update cooldown tracking
        lastTriggerTime = sessionTime
        lastTierTriggerTimes[match.keyword.tier] = sessionTime

        return SmartBookmarkResult(
            confidence: match.score,
            triggerPhrase: match.keyword.phrase,
            tier: match.keyword.tier,
            label: match.keyword.label
        )
    }

    /// Reset state for a new session.
    func reset() {
        lastTriggerTime = -100
        lastTierTriggerTimes = [:]
    }

    // MARK: - Helpers

    private func containsDateReference(_ text: String) -> Bool {
        let dateWords = ["monday", "tuesday", "wednesday", "thursday", "friday",
                         "saturday", "sunday", "tomorrow", "next week", "next class",
                         "january", "february", "march", "april", "may", "june",
                         "july", "august", "september", "october", "november", "december"]
        return dateWords.contains { text.contains($0) }
    }

    private func containsNumber(_ text: String) -> Bool {
        text.contains(where: \.isNumber)
    }
}
