import SwiftUI
import EventKit

// MARK: - ExportPreviewSheet

/// Review and edit TODOs before exporting to Reminders/Calendar.
/// Each row has a checkbox, editable title, date picker, and Reminder vs Calendar toggle.
struct ExportPreviewSheet: View {
    let todos: [TodoItem]
    let sessionId: UUID?
    let sessionTitle: String
    var onComplete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var items: [EditableTodoItem] = []
    @State private var isExporting = false
    @State private var exportResult: ExportResult?

    var body: some View {
        NavigationView {
            ZStack {
                NoteVConfig.Design.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Summary bar
                    summaryBar

                    // Item list
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach($items) { $item in
                                exportRow(item: $item)
                                Divider()
                                    .background(NoteVConfig.Design.surface)
                            }
                        }
                        .padding(.vertical, 8)
                    }

                    // Export button
                    exportButton
                }
            }
            .navigationTitle("Export Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(NoteVConfig.Design.textSecondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(allSelected ? "Deselect All" : "Select All") {
                        let newValue = !allSelected
                        for index in items.indices {
                            items[index].isSelected = newValue
                        }
                    }
                    .foregroundColor(NoteVConfig.Design.accent)
                }
            }
        }
        .onAppear {
            items = todos.map { EditableTodoItem(from: $0) }
        }
        .alert(exportResult?.title ?? "", isPresented: Binding(
            get: { exportResult != nil },
            set: { if !$0 { exportResult = nil } }
        )) {
            Button("Done") {
                exportResult = nil
                dismiss()
                onComplete?()
            }
        } message: {
            Text(exportResult?.message ?? "")
        }
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack {
            Text("\(selectedCount) of \(items.count) selected")
                .font(.subheadline)
                .foregroundColor(NoteVConfig.Design.textSecondary)

            Spacer()

            HStack(spacing: 12) {
                Label("\(reminderCount)", systemImage: "checklist")
                Label("\(calendarCount)", systemImage: "calendar")
            }
            .font(.caption)
            .foregroundColor(NoteVConfig.Design.textSecondary)
        }
        .padding(.horizontal, NoteVConfig.Design.padding)
        .padding(.vertical, 10)
        .background(NoteVConfig.Design.surface)
    }

    // MARK: - Export Row

    private func exportRow(item: Binding<EditableTodoItem>) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button {
                item.wrappedValue.isSelected.toggle()
            } label: {
                Image(systemName: item.wrappedValue.isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(item.wrappedValue.isSelected ? NoteVConfig.Design.accent : NoteVConfig.Design.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                // Editable title
                TextField("Title", text: item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(NoteVConfig.Design.textPrimary)

                HStack(spacing: 8) {
                    // Category badge
                    Text(categoryLabel(item.wrappedValue.category))
                        .font(.caption2)
                        .foregroundColor(priorityColor(item.wrappedValue.priority))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(priorityColor(item.wrappedValue.priority).opacity(0.15))
                        .cornerRadius(4)

                    // Priority badge
                    Text(item.wrappedValue.priority.rawValue.capitalized)
                        .font(.caption2)
                        .foregroundColor(priorityColor(item.wrappedValue.priority))
                }

                // Date picker
                HStack {
                    if item.wrappedValue.hasDueDate {
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { item.wrappedValue.dueDate ?? Date() },
                                set: { item.wrappedValue.dueDate = $0 }
                            ),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(NoteVConfig.Design.accent)

                        Button {
                            item.wrappedValue.hasDueDate = false
                            item.wrappedValue.dueDate = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(NoteVConfig.Design.textSecondary)
                        }
                    } else {
                        Button {
                            item.wrappedValue.hasDueDate = true
                            item.wrappedValue.dueDate = Date().addingTimeInterval(86400) // tomorrow
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar.badge.plus")
                                Text("Add Date")
                            }
                            .font(.caption)
                            .foregroundColor(NoteVConfig.Design.accent)
                        }
                    }

                    Spacer()

                    // Reminder vs Calendar toggle
                    Button {
                        item.wrappedValue.isCalendarEvent.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: item.wrappedValue.isCalendarEvent ? "calendar" : "checklist")
                            Text(item.wrappedValue.isCalendarEvent ? "Event" : "Reminder")
                        }
                        .font(.caption)
                        .foregroundColor(item.wrappedValue.isCalendarEvent ? .orange : NoteVConfig.Design.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (item.wrappedValue.isCalendarEvent ? Color.orange : NoteVConfig.Design.accent).opacity(0.12)
                        )
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, NoteVConfig.Design.padding)
        .padding(.vertical, 10)
        .opacity(item.wrappedValue.isSelected ? 1.0 : 0.5)
    }

    // MARK: - Export Button

    private var exportButton: some View {
        Button(action: { exportSelected() }) {
            if isExporting {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(NoteVConfig.Design.accent.opacity(0.7))
                    .cornerRadius(NoteVConfig.Design.cornerRadius)
            } else {
                Text("Export \(selectedCount) Item\(selectedCount == 1 ? "" : "s")")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(selectedCount > 0 ? NoteVConfig.Design.accent : NoteVConfig.Design.textSecondary)
                    .cornerRadius(NoteVConfig.Design.cornerRadius)
            }
        }
        .disabled(selectedCount == 0 || isExporting)
        .padding(.horizontal, NoteVConfig.Design.padding)
        .padding(.vertical, 12)
        .background(NoteVConfig.Design.background)
    }

    // MARK: - Actions

    private func exportSelected() {
        isExporting = true
        let selectedItems = items.filter(\.isSelected)

        Task { @MainActor in
            do {
                let service = ReminderSyncService.shared

                // Export reminders
                let reminderItems = selectedItems
                    .filter { !$0.isCalendarEvent }
                    .map { $0.toTodoItem() }

                if !reminderItems.isEmpty {
                    let granted = try await service.requestAccess()
                    guard granted else {
                        exportResult = ExportResult(title: "Access Denied", message: "Enable Reminders in Settings > Privacy > Reminders.")
                        isExporting = false
                        return
                    }
                    _ = try await service.exportToReminders(reminderItems, sessionTitle: sessionTitle, sessionId: sessionId)
                    NSLog("[ExportPreviewSheet] Exported \(reminderItems.count) reminders")
                }

                // Export calendar events
                let calendarItems = selectedItems
                    .filter { $0.isCalendarEvent }
                    .map { $0.toTodoItem() }

                if !calendarItems.isEmpty {
                    let calGranted = try await service.requestCalendarAccess()
                    guard calGranted else {
                        exportResult = ExportResult(title: "Access Denied", message: "Enable Calendar in Settings > Privacy > Calendar.")
                        isExporting = false
                        return
                    }
                    try await service.exportToCalendar(calendarItems, sessionTitle: sessionTitle)
                    NSLog("[ExportPreviewSheet] Exported \(calendarItems.count) calendar events")
                }

                UINotificationFeedbackGenerator().notificationOccurred(.success)
                let total = reminderItems.count + calendarItems.count
                exportResult = ExportResult(
                    title: "Exported",
                    message: "\(total) item\(total == 1 ? "" : "s") exported successfully."
                )
            } catch {
                NSLog("[ExportPreviewSheet] Export failed: \(error.localizedDescription)")
                exportResult = ExportResult(title: "Export Failed", message: error.localizedDescription)
            }
            isExporting = false
        }
    }

    // MARK: - Computed

    private var selectedCount: Int { items.filter(\.isSelected).count }
    private var reminderCount: Int { items.filter { $0.isSelected && !$0.isCalendarEvent }.count }
    private var calendarCount: Int { items.filter { $0.isSelected && $0.isCalendarEvent }.count }
    private var allSelected: Bool { items.allSatisfy(\.isSelected) }

    private func priorityColor(_ priority: TodoPriority) -> Color {
        switch priority {
        case .high: return NoteVConfig.Design.bookmarkHighlight
        case .medium: return NoteVConfig.Design.accent
        case .low: return NoteVConfig.Design.textSecondary
        }
    }

    private func categoryLabel(_ category: TodoCategory) -> String {
        switch category {
        case .homework: return "Homework"
        case .reading: return "Reading"
        case .examPrep: return "Exam Prep"
        case .project: return "Project"
        case .quiz: return "Quiz"
        case .lab: return "Lab"
        case .attendance: return "Attendance"
        case .other: return "Task"
        }
    }
}

// MARK: - EditableTodoItem

struct EditableTodoItem: Identifiable {
    let id: UUID
    var title: String
    let category: TodoCategory
    let priority: TodoPriority
    var dueDate: Date?
    var hasDueDate: Bool
    var isCalendarEvent: Bool
    let sourceTimestamp: TimeInterval
    let sourceQuote: String
    let confidence: Int
    let dateQuote: String?
    var isSelected: Bool

    init(from todo: TodoItem) {
        self.id = todo.id
        self.title = todo.title
        self.category = todo.category
        self.priority = todo.priority
        self.dueDate = todo.resolvedDueDate
        self.hasDueDate = todo.resolvedDueDate != nil
        self.isCalendarEvent = todo.isCalendarEvent
        self.sourceTimestamp = todo.sourceTimestamp
        self.sourceQuote = todo.sourceQuote
        self.confidence = todo.confidence
        self.dateQuote = todo.dateQuote
        self.isSelected = !todo.isSynced
    }

    func toTodoItem() -> TodoItem {
        TodoItem(
            id: id,
            title: title,
            category: category,
            priority: priority,
            dateQuote: dateQuote,
            resolvedDueDate: hasDueDate ? dueDate : nil,
            isCalendarEvent: isCalendarEvent,
            sourceTimestamp: sourceTimestamp,
            sourceQuote: sourceQuote,
            confidence: confidence
        )
    }
}

// MARK: - ExportResult

private struct ExportResult {
    let title: String
    let message: String
}
