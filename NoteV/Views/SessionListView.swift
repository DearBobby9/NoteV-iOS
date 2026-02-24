import SwiftUI

// MARK: - SessionListView

/// List of past recording sessions.
/// TODO: Phase 2 — Load sessions from SessionStore, navigation to NotesResultView
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
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.metadata.title)
                                .font(.headline)
                                .foregroundColor(NoteVConfig.Design.textPrimary)

                            Text(session.metadata.startDate, style: .date)
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
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SessionListView()
            .environmentObject(AppState())
    }
}
