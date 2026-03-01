import SwiftUI

// MARK: - SessionListView

/// List of past recording sessions with navigation to view notes.
struct SessionListView: View {
    @EnvironmentObject var appState: AppState
    @State private var sessionToDelete: SessionData?

    var body: some View {
        ZStack {
            NoteVConfig.Design.background
                .ignoresSafeArea()

            if appState.pastSessions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(NoteVConfig.Design.textSecondary)

                    Text("No sessions yet")
                        .font(.headline)
                        .foregroundColor(NoteVConfig.Design.textSecondary)

                    Text("Start a class to begin recording")
                        .font(.subheadline)
                        .foregroundColor(NoteVConfig.Design.textSecondary)
                }
            } else {
                List(appState.pastSessions) { session in
                    Button(action: {
                        appState.currentSession = session
                        appState.generatedNotes = session.notes
                        appState.extractedTodos = session.todos ?? []
                        appState.sessionStatus = .complete
                        appState.navigationPath.append(NavigationDestination.pastSessionResult)
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(session.metadata.title)
                                        .font(.headline)
                                        .foregroundColor(NoteVConfig.Design.textPrimary)

                                    if let courseName = session.courseName {
                                        CourseBadge(name: courseName, colorHex: "#00E5FF")
                                    }
                                }

                                HStack(spacing: 8) {
                                    Text(session.metadata.startDate, style: .date)
                                    Text(formatDuration(session.metadata.durationSeconds))
                                }
                                .font(.subheadline)
                                .foregroundColor(NoteVConfig.Design.textSecondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text("\(session.frames.count) frames")
                                    .font(.caption)
                                    .foregroundColor(NoteVConfig.Design.textSecondary)

                                if session.notes != nil {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    .listRowBackground(NoteVConfig.Design.surface)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            sessionToDelete = session
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .confirmationDialog(
                    "Delete this session?",
                    isPresented: Binding(
                        get: { sessionToDelete != nil },
                        set: { if !$0 { sessionToDelete = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        if let session = sessionToDelete {
                            deleteSession(session)
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        sessionToDelete = nil
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func deleteSession(_ session: SessionData) {
        do {
            try SessionStore().delete(sessionId: session.id)
            appState.pastSessions.removeAll { $0.id == session.id }
            NSLog("[SessionListView] Deleted session: \(session.id)")
        } catch {
            NSLog("[SessionListView] ERROR deleting session: \(error.localizedDescription)")
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SessionListView()
            .environmentObject(AppState())
    }
}
