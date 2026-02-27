import SwiftUI

// MARK: - NotesResultView

/// Displays generated notes: progress indicator while generating, then rendered notes with images.
struct NotesResultView: View {
    @EnvironmentObject var appState: AppState
    @State private var pdfURL: URL?
    @State private var pdfSourceSessionId: UUID?
    @State private var pdfSourceGeneratedAt: Date?

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
                    // Notes ready — timeline view with bottom action bar
                    VStack(spacing: 0) {
                        TimelineNoteView(notes: notes, sessionId: appState.currentSession?.id)

                        // Action buttons bar
                        HStack(spacing: 16) {
                            // Text share button
                            ShareLink(item: notesAsText(notes)) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Text")
                                }
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundColor(NoteVConfig.Design.accent)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(NoteVConfig.Design.surface)
                                .cornerRadius(NoteVConfig.Design.cornerRadius)
                            }

                            // PDF share button
                            if let url = currentPDFURL(for: notes) {
                                ShareLink(item: url) {
                                    HStack {
                                        Image(systemName: "doc.richtext")
                                        Text("PDF")
                                    }
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(NoteVConfig.Design.accent)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(NoteVConfig.Design.surface)
                                    .cornerRadius(NoteVConfig.Design.cornerRadius)
                                }
                            } else {
                                Button(action: { generatePDF(notes: notes) }) {
                                    HStack {
                                        Image(systemName: "doc.richtext")
                                        Text("PDF")
                                    }
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .foregroundColor(NoteVConfig.Design.accent)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(NoteVConfig.Design.surface)
                                    .cornerRadius(NoteVConfig.Design.cornerRadius)
                                }
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
                        .padding(.vertical, 12)
                        .background(NoteVConfig.Design.background)
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

    private func generatePDF(notes: StructuredNotes) {
        invalidatePDFCache()

        let generator = PDFGenerator()
        let data = generator.generatePDF(notes: notes, sessionId: appState.currentSession?.id)
        let sanitizedTitle = notes.title.replacingOccurrences(of: "/", with: "-")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(sanitizedTitle).pdf")
        do {
            try data.write(to: tempURL, options: .atomic)
            pdfURL = tempURL
            pdfSourceSessionId = appState.currentSession?.id
            pdfSourceGeneratedAt = notes.generatedAt
            NSLog("[NotesResultView] PDF generated: \(tempURL.lastPathComponent), \(data.count) bytes")
        } catch {
            NSLog("[NotesResultView] ERROR writing PDF: \(error.localizedDescription)")
            invalidatePDFCache()
        }
    }

    private func retryNoteGeneration() {
        guard let session = appState.currentSession else { return }
        NSLog("[NotesResultView] Retrying note generation")
        invalidatePDFCache()
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
            var header = "## \(section.title)"
            if let range = section.formattedTimeRange {
                header += " [\(range)]"
            }
            text += "\(header)\n\(section.content)\n\n"
        }

        text += "\n---\nGenerated by NoteV using \(notes.modelUsed)"
        return text
    }

    private func currentPDFURL(for notes: StructuredNotes) -> URL? {
        guard let url = pdfURL,
              pdfSourceSessionId == appState.currentSession?.id,
              pdfSourceGeneratedAt == notes.generatedAt else {
            return nil
        }
        return url
    }

    private func invalidatePDFCache() {
        if let url = pdfURL {
            try? FileManager.default.removeItem(at: url)
        }
        pdfURL = nil
        pdfSourceSessionId = nil
        pdfSourceGeneratedAt = nil
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NotesResultView()
            .environmentObject(AppState())
    }
}
