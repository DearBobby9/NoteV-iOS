import Foundation

// MARK: - TodoCategory

/// Category of an extracted action item.
enum TodoCategory: String, Codable, CaseIterable, Sendable {
    case homework
    case reading
    case examPrep = "exam_prep"
    case project
    case quiz
    case lab
    case attendance
    case other
}

// MARK: - TodoPriority

/// Priority level for an action item.
enum TodoPriority: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low
}

// MARK: - TodoItem

/// A single action item extracted from a lecture transcript.
struct TodoItem: Identifiable, Codable, Sendable {
    let id: UUID
    let title: String                    // Imperative phrase: "Submit Lab Report 3"
    let category: TodoCategory
    let priority: TodoPriority
    let dateQuote: String?               // Verbatim from transcript: "due next Friday"
    var resolvedDueDate: Date?           // Resolved by Swift NSDataDetector, not LLM
    let isCalendarEvent: Bool            // true → EKEvent (specific date+time), false → EKReminder
    let sourceTimestamp: TimeInterval    // When mentioned in transcript (seconds)
    let sourceQuote: String              // Verbatim sentence from transcript
    let confidence: Int                  // 1-5 (5 = unambiguous deadline)
    var isSynced: Bool                   // Exported to iOS Reminders?
    var eventKitIdentifier: String?      // EKCalendarItem identifier for tracking

    init(
        id: UUID = UUID(),
        title: String,
        category: TodoCategory = .other,
        priority: TodoPriority = .medium,
        dateQuote: String? = nil,
        resolvedDueDate: Date? = nil,
        isCalendarEvent: Bool = false,
        sourceTimestamp: TimeInterval = 0,
        sourceQuote: String = "",
        confidence: Int = 3,
        isSynced: Bool = false,
        eventKitIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.priority = priority
        self.dateQuote = dateQuote
        self.resolvedDueDate = resolvedDueDate
        self.isCalendarEvent = isCalendarEvent
        self.sourceTimestamp = sourceTimestamp
        self.sourceQuote = sourceQuote
        self.confidence = confidence
        self.isSynced = isSynced
        self.eventKitIdentifier = eventKitIdentifier
    }
}
