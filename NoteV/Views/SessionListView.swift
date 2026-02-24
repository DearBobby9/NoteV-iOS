import SwiftUI

// MARK: - SessionListView

/// List of past recording sessions with navigation to view notes.
struct SessionListView: View {
    @EnvironmentObject var appState: AppState

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
                        appState.sessionStatus = session.notes != nil ? .complete : .idle
                        appState.navigationPath.append(NavigationDestination.notesResult)
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.metadata.title)
                                    .font(.headline)
                                    .foregroundColor(NoteVConfig.Design.textPrimary)

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
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
