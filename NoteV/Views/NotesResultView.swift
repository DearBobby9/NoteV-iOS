import SwiftUI

// MARK: - NotesResultView

/// Displays generated notes: progress indicator while generating, then rendered notes with images.
/// TODO: Phase 3 — Wire up NoteGenerator, render StructuredNotes
struct NotesResultView: View {
    @EnvironmentObject var appState: AppState
    let session: SessionData

    var body: some View {
        ZStack {
            NoteVConfig.Design.background
                .ignoresSafeArea()

            Group {
                if appState.sessionStatus == .generatingNotes {
                    // Generating state
                    VStack(spacing: 24) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: NoteVConfig.Design.accent))
                            .scaleEffect(1.5)

                        Text("Generating Notes...")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(NoteVConfig.Design.textPrimary)

                        Text("Analyzing \(session.frames.count) frames and \(session.transcriptSegments.count) transcript segments")
                            .font(.subheadline)
                            .foregroundColor(NoteVConfig.Design.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else if let notes = session.notes {
                    // Notes ready
                    ScrollView {
                        MultimodalNoteView(notes: notes)
                            .padding(NoteVConfig.Design.padding)
                    }
                } else {
                    // No notes available
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 48))
                            .foregroundColor(NoteVConfig.Design.textSecondary)

                        Text("No notes generated yet")
                            .font(.headline)
                            .foregroundColor(NoteVConfig.Design.textSecondary)
                    }
                }
            }
        }
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NotesResultView(session: SessionData())
            .environmentObject(AppState())
    }
}
