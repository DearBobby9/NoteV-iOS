import SwiftUI

// MARK: - NotesResultView

/// Displays generated notes: progress indicator while generating, then rendered notes with images.
struct NotesResultView: View {
    @EnvironmentObject var appState: AppState

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

                        if let session = appState.currentSession {
                            Text("Analyzing \(session.frames.count) frames and \(session.transcriptSegments.count) transcript segments")
                                .font(.subheadline)
                                .foregroundColor(NoteVConfig.Design.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }

                        // Animated dots
                        HStack(spacing: 8) {
                            ForEach(0..<3, id: \.self) { index in
                                Circle()
                                    .fill(NoteVConfig.Design.accent)
                                    .frame(width: 8, height: 8)
                                    .opacity(0.3)
                                    .animation(
                                        .easeInOut(duration: 0.6)
                                        .repeatForever()
                                        .delay(Double(index) * 0.2),
                                        value: appState.sessionStatus
                                    )
                            }
                        }
                    }
                } else if let notes = appState.generatedNotes {
                    // Notes ready
                    ScrollView {
                        VStack(spacing: 16) {
                            MultimodalNoteView(notes: notes, sessionId: appState.currentSession?.id)
                                .padding(NoteVConfig.Design.padding)

                            // Action buttons
                            HStack(spacing: 16) {
                                // Share button
                                ShareLink(item: notesAsText(notes)) {
                                    HStack {
                                        Image(systemName: "square.and.arrow.up")
                                        Text("Share")
                                    }
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(NoteVConfig.Design.accent)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(NoteVConfig.Design.surface)
                                    .cornerRadius(NoteVConfig.Design.cornerRadius)
                                }

                                // Done button
                                Button(action: {
                                    appState.navigationPath = NavigationPath()
                                    appState.reset()
                                }) {
                                    HStack {
                                        Image(systemName: "checkmark.circle")
                                        Text("Done")
                                    }
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(NoteVConfig.Design.accent)
                                    .cornerRadius(NoteVConfig.Design.cornerRadius)
                                }
                            }
                            .padding(.horizontal, NoteVConfig.Design.padding)
                            .padding(.bottom, 40)
                        }
                    }
                } else if case .error(let message) = appState.sessionStatus {
                    // Error state
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)

                        Text("Note Generation Failed")
                            .font(.headline)
                            .foregroundColor(NoteVConfig.Design.textPrimary)

                        Text(message)
                            .font(.subheadline)
                            .foregroundColor(NoteVConfig.Design.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        // Session summary even without notes
                        if let session = appState.currentSession {
                            sessionSummaryView(session)
                        }

                        HStack(spacing: 16) {
                            Button(action: {
                                appState.navigationPath = NavigationPath()
                                appState.reset()
                            }) {
                                Text("Back to Home")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(NoteVConfig.Design.accent)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(NoteVConfig.Design.surface)
                                    .cornerRadius(NoteVConfig.Design.cornerRadius)
                            }

                            Button(action: {
                                retryNoteGeneration()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Retry")
                                }
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundColor(.black)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(NoteVConfig.Design.accent)
                                .cornerRadius(NoteVConfig.Design.cornerRadius)
                            }
                        }
                        .padding(.top, 12)
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
        .navigationBarBackButtonHidden(appState.sessionStatus == .generatingNotes)
    }

    // MARK: - Actions

    private func retryNoteGeneration() {
        guard let session = appState.currentSession else { return }
        NSLog("[NotesResultView] Retrying note generation")
        appState.sessionStatus = .generatingNotes

        Task {
            do {
                let generator = NoteGenerator()
                let notes = try await generator.generateNotes(from: session)
                appState.generatedNotes = notes

                // Backfill title from generated notes
                var updatedSession = session
                updatedSession.metadata.title = notes.title
                updatedSession.notes = notes
                appState.currentSession = updatedSession

                let store = SessionStore()
                try store.save(session: updatedSession)

                appState.sessionStatus = .complete
                NSLog("[NotesResultView] Retry succeeded, title: \(notes.title)")
            } catch {
                NSLog("[NotesResultView] Retry failed: \(error.localizedDescription)")
                appState.sessionStatus = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Helpers

    private func sessionSummaryView(_ session: SessionData) -> some View {
        VStack(spacing: 8) {
            Text("Session Captured:")
                .font(.callout)
                .foregroundColor(NoteVConfig.Design.textSecondary)

            HStack(spacing: 20) {
                Label("\(session.frames.count) frames", systemImage: "photo")
                Label("\(session.transcriptSegments.count) segments", systemImage: "text.bubble")
                Label("\(session.bookmarks.count) bookmarks", systemImage: "bookmark")
            }
            .font(.caption)
            .foregroundColor(NoteVConfig.Design.textSecondary)
        }
        .padding()
        .background(NoteVConfig.Design.surface)
        .cornerRadius(NoteVConfig.Design.cornerRadius)
        .padding(.horizontal, 40)
    }

    private func notesAsText(_ notes: StructuredNotes) -> String {
        var text = "# \(notes.title)\n\n"
        text += "## Summary\n\(notes.summary)\n\n"

        if !notes.keyTakeaways.isEmpty {
            text += "## Key Takeaways\n"
            for takeaway in notes.keyTakeaways {
                text += "- \(takeaway)\n"
            }
            text += "\n"
        }

        for section in notes.sections.sorted(by: { $0.order < $1.order }) {
            text += "## \(section.title)\n\(section.content)\n\n"
        }

        text += "\n---\nGenerated by NoteV using \(notes.modelUsed)"
        return text
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NotesResultView()
            .environmentObject(AppState())
    }
}
