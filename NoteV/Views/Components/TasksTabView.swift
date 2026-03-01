import SwiftUI

// MARK: - TasksTabView

/// Displays extracted action items grouped by priority.
/// Used as the third tab in SessionResultView.
struct TasksTabView: View {
    let todos: [TodoItem]
    let sessionId: UUID?
    var sessionTitle: String = "NoteV Session"
    var onExportToReminders: (([TodoItem]) -> Void)?

    @State private var expandedItemId: UUID?
    @State private var showExportSheet = false

    private var highPriority: [TodoItem] { todos.filter { $0.priority == .high } }
    private var mediumPriority: [TodoItem] { todos.filter { $0.priority == .medium } }
    private var lowPriority: [TodoItem] { todos.filter { $0.priority == .low } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Export all button
                if !todos.isEmpty {
                    exportAllBar
                }

                // Priority sections
                if !highPriority.isEmpty {
                    prioritySection(title: "High Priority", items: highPriority, color: NoteVConfig.Design.bookmarkHighlight)
                }
                if !mediumPriority.isEmpty {
                    prioritySection(title: "Medium Priority", items: mediumPriority, color: NoteVConfig.Design.accent)
                }
                if !lowPriority.isEmpty {
                    prioritySection(title: "Low Priority", items: lowPriority, color: NoteVConfig.Design.textSecondary)
                }
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - Export All Bar

    private var exportAllBar: some View {
        HStack {
            Text("\(todos.count) action item\(todos.count == 1 ? "" : "s") found")
                .font(.subheadline)
                .foregroundColor(NoteVConfig.Design.textSecondary)

            Spacer()

            Button(action: {
                showExportSheet = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                    Text("Export")
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(NoteVConfig.Design.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(NoteVConfig.Design.accent.opacity(0.15))
                .cornerRadius(8)
            }
            .sheet(isPresented: $showExportSheet) {
                ExportPreviewSheet(
                    todos: todos,
                    sessionId: sessionId,
                    sessionTitle: sessionTitle,
                    onComplete: {
                        onExportToReminders?(todos)
                    }
                )
            }
        }
        .padding(.horizontal, NoteVConfig.Design.padding)
        .padding(.bottom, 12)
    }

    // MARK: - Priority Section

    private func prioritySection(title: String, items: [TodoItem], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, NoteVConfig.Design.padding)
            .padding(.top, 12)

            // Items
            ForEach(items) { item in
                todoRow(item, accentColor: color)
            }
        }
    }

    // MARK: - Todo Row

    private func todoRow(_ item: TodoItem, accentColor: Color) -> some View {
        let isExpanded = expandedItemId == item.id

        return VStack(alignment: .leading, spacing: 0) {
            // Main row
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedItemId = isExpanded ? nil : item.id
                }
            }) {
                HStack(alignment: .top, spacing: 12) {
                    // Timestamp
                    Text(formatTimestamp(item.sourceTimestamp))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundColor(NoteVConfig.Design.textSecondary)
                        .frame(width: 36, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 4) {
                        // Title
                        Text(item.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(NoteVConfig.Design.textPrimary)
                            .multilineTextAlignment(.leading)

                        // Metadata row
                        HStack(spacing: 8) {
                            // Category badge
                            Text(categoryLabel(item.category))
                                .font(.caption2)
                                .foregroundColor(accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accentColor.opacity(0.15))
                                .cornerRadius(4)

                            // Due date
                            if let date = item.resolvedDueDate {
                                HStack(spacing: 2) {
                                    Image(systemName: "calendar")
                                    Text(date, style: .date)
                                }
                                .font(.caption2)
                                .foregroundColor(NoteVConfig.Design.textSecondary)
                            } else if let quote = item.dateQuote {
                                HStack(spacing: 2) {
                                    Image(systemName: "clock")
                                    Text(quote)
                                }
                                .font(.caption2)
                                .foregroundColor(NoteVConfig.Design.textSecondary)
                                .lineLimit(1)
                            }

                            // Sync indicator
                            if item.isSynced {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }
                    }

                    Spacer()

                    // Chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(NoteVConfig.Design.textSecondary)
                }
                .padding(.horizontal, NoteVConfig.Design.padding)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            // Expanded detail
            if isExpanded {
                expandedDetail(item, accentColor: accentColor)
            }

            // Separator
            Divider()
                .background(NoteVConfig.Design.surface)
                .padding(.leading, NoteVConfig.Design.padding + 48)
        }
    }

    // MARK: - Expanded Detail

    private func expandedDetail(_ item: TodoItem, accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Source quote
            if !item.sourceQuote.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(accentColor.opacity(0.5))
                        .frame(width: 2)

                    Text("\"\(item.sourceQuote)\"")
                        .font(.caption)
                        .foregroundColor(NoteVConfig.Design.textSecondary)
                        .italic()
                }
            }

            // Confidence
            HStack(spacing: 4) {
                Text("Confidence:")
                    .font(.caption2)
                    .foregroundColor(NoteVConfig.Design.textSecondary)
                ForEach(1...5, id: \.self) { level in
                    Circle()
                        .fill(level <= item.confidence
                              ? accentColor
                              : NoteVConfig.Design.textSecondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }

            // Export single item
            Button(action: {
                onExportToReminders?([item])
            }) {
                HStack(spacing: 4) {
                    Image(systemName: item.isSynced ? "checkmark.circle" : "square.and.arrow.up")
                    Text(item.isSynced ? "Exported" : "Export to Reminders")
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(item.isSynced ? .green : NoteVConfig.Design.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    (item.isSynced ? Color.green : NoteVConfig.Design.accent).opacity(0.12)
                )
                .cornerRadius(6)
            }
            .disabled(item.isSynced)
        }
        .padding(.leading, NoteVConfig.Design.padding + 48)
        .padding(.trailing, NoteVConfig.Design.padding)
        .padding(.bottom, 10)
    }

    // MARK: - Helpers

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
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
