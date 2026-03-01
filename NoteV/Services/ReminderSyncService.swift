import EventKit
import Foundation

// MARK: - ReminderSyncError

enum ReminderSyncError: LocalizedError {
    case accessDenied
    case noValidSource
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Reminders access denied. Update in Settings > Privacy > Reminders."
        case .noValidSource:
            return "No valid reminder source found. Check iCloud or local storage."
        case .saveFailed(let detail):
            return "Failed to save reminder: \(detail)"
        }
    }
}

// MARK: - ReminderSyncService

/// Wraps EventKit to export TodoItems to iOS Reminders.
/// Single shared instance — EKEventStore is expensive to initialize.
final class ReminderSyncService: @unchecked Sendable {

    @MainActor static let shared = ReminderSyncService()

    private let eventStore = EKEventStore()
    @MainActor private(set) var hasAccess = false

    private static let listName = "NoteV Tasks"

    private init() {}

    // MARK: - Access

    /// Request full access to Reminders (iOS 17+).
    /// Returns true if access was granted.
    @MainActor
    func requestAccess() async throws -> Bool {
        let granted = try await eventStore.requestFullAccessToReminders()
        hasAccess = granted
        NSLog("[ReminderSyncService] Access \(granted ? "granted" : "denied")")
        return granted
    }

    /// Check current authorization status without prompting.
    func checkAuthorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    // MARK: - Export

    /// Export TodoItems to iOS Reminders.
    /// Returns updated items with `isSynced` and `eventKitIdentifier` set.
    /// Runs EKEventStore I/O off the main thread to avoid UI hitches.
    func exportToReminders(_ items: [TodoItem], sessionTitle: String, sessionId: UUID?) async throws -> [TodoItem] {
        let hasAccess = await MainActor.run { self.hasAccess }
        guard hasAccess else {
            throw ReminderSyncError.accessDenied
        }

        let list = try fetchOrCreateList(named: Self.listName)

        // Track item→identifier mapping; only mark synced after commit succeeds
        var pendingItems: [(index: Int, identifier: String)] = []
        var updatedItems = items

        for (index, item) in items.enumerated() {
            // Skip already synced items
            if item.isSynced, item.eventKitIdentifier != nil {
                continue
            }

            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = item.title
            reminder.calendar = list

            // Priority: 1-4 = high, 5 = medium, 6-9 = low
            switch item.priority {
            case .high: reminder.priority = 1
            case .medium: reminder.priority = 5
            case .low: reminder.priority = 9
            }

            // Due date
            if let dueDate = item.resolvedDueDate {
                let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
                let cal = Calendar.current
                reminder.startDateComponents = cal.dateComponents(components, from: dueDate)
                reminder.dueDateComponents = cal.dateComponents(components, from: dueDate)

                // Add alarm at due date
                let alarm = EKAlarm(relativeOffset: 0)
                reminder.addAlarm(alarm)
            }

            // Notes: source quote + session context
            var notes = ""
            if !item.sourceQuote.isEmpty {
                notes += "From lecture: \"\(item.sourceQuote)\"\n"
            }
            if let dateQuote = item.dateQuote {
                notes += "Date mentioned: \(dateQuote)\n"
            }
            notes += "Session: \(sessionTitle)"
            reminder.notes = notes

            // Deep link URL
            if let sessionId = sessionId {
                let timestamp = Int(item.sourceTimestamp)
                reminder.url = URL(string: "notev://session/\(sessionId)?t=\(timestamp)")
            }

            // Stage (don't commit yet — batch)
            try eventStore.save(reminder, commit: false)
            pendingItems.append((index: index, identifier: reminder.calendarItemIdentifier))
        }

        // Single disk write for all reminders
        try eventStore.commit()

        // Only mark synced after commit succeeds
        for pending in pendingItems {
            updatedItems[pending.index].isSynced = true
            updatedItems[pending.index].eventKitIdentifier = pending.identifier
        }

        NSLog("[ReminderSyncService] Batch committed \(pendingItems.count) reminders to '\(Self.listName)'")
        return updatedItems
    }

    // MARK: - Reminder List

    /// Returns the "NoteV Tasks" reminder list, creating it if needed.
    private func fetchOrCreateList(named name: String) throws -> EKCalendar {
        // Check if list already exists
        let existing = eventStore.calendars(for: .reminder)
        if let found = existing.first(where: { $0.title == name }) {
            return found
        }

        // Determine best source
        guard let source = bestReminderSource() else {
            throw ReminderSyncError.noValidSource
        }

        let list = EKCalendar(for: .reminder, eventStore: eventStore)
        list.title = name
        list.source = source

        try eventStore.saveCalendar(list, commit: true)
        NSLog("[ReminderSyncService] Created reminder list '\(name)' (source: \(source.title))")
        return list
    }

    private func bestReminderSource() -> EKSource? {
        // Use same source as default reminder calendar
        if let defaultSource = eventStore.defaultCalendarForNewReminders()?.source {
            return defaultSource
        }
        // Fallback: iCloud
        let iCloud = eventStore.sources.first {
            $0.sourceType == .calDAV && $0.title == "iCloud"
        }
        // Final fallback: local
        let local = eventStore.sources.first { $0.sourceType == .local }
        return iCloud ?? local
    }
}
