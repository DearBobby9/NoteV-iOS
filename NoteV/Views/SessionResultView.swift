import SwiftUI

// MARK: - SessionResultView

/// Two-tab post-recording view: Layer 1 (Polished Transcript Timeline) + Layer 2 (AI Notes).
/// Replaces NotesResultView as the primary post-recording destination.
struct SessionResultView: View {
    @EnvironmentObject var appState: AppState

    /// True when navigated from SessionListView (past session browsing)
    var isBrowsingPastSession: Bool = false

    @State private var selectedTab: ResultTab = .timeline
    @State private var pdfURL: URL?
    @State private var pdfSourceSessionId: UUID?
    @State private var pdfSourceGeneratedAt: Date?
    @State private var rawSegments: [TranscriptSegment] = []

    enum ResultTab: String, CaseIterable {
        case timeline = "Timeline"
        case aiNotes = "AI Notes"
    }

    var body: some View {
        ZStack {
            NoteVConfig.Design.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Tab picker
                Picker("View", selection: $selectedTab) {
                    ForEach(ResultTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, NoteVConfig.Design.padding)
                .padding(.vertical, 8)

                // Content
                switch selectedTab {
                case .timeline:
                    timelineContent
                case .aiNotes:
                    aiNotesContent
                }

                // Bottom action bar
                actionBar
            }
        }
        .navigationTitle(appState.currentSession?.metadata.title ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarBackButtonHidden(
            appState.sessionStatus == .polishing || appState.sessionStatus == .generatingNotes
        )
        .onAppear {
            if let session = appState.currentSession {
                rawSegments = session.transcriptSegments
                    .filter { $0.isFinal }
                    .sorted { $0.startTime < $1.startTime }
            }
        }
    }

    // MARK: - Timeline Tab (Layer 1)

    @ViewBuilder
    private var timelineContent: some View {
        if appState.sessionStatus == .polishing {
            polishingProgressView
        } else if let transcript = appState.currentSession?.polishedTranscript, !transcript.segments.isEmpty {
            TranscriptTimelineView(
                transcript: transcript,
                sessionId: appState.currentSession?.id
            )
        } else if case .error = appState.sessionStatus {
            // Polishing failed — show raw transcript as fallback
            rawTranscriptFallback(showErrorBanner: true)
        } else if !rawSegments.isEmpty {
            // No polished transcript (old session) — show raw transcript
            rawTranscriptFallback(showErrorBanner: false)
        } else {
            // No transcript at all
            placeholderView(
                icon: "text.alignleft",
                title: "No transcript available",
                detail: nil
            )
        }
    }

    // MARK: - AI Notes Tab (Layer 2)

    @ViewBuilder
    private var aiNotesContent: some View {
        if appState.sessionStatus == .polishing || appState.sessionStatus == .generatingNotes {
            notesGeneratingView
        } else if let notes = appState.generatedNotes {
            TimelineNoteView(notes: notes, sessionId: appState.currentSession?.id)
        } else if case .error(let message) = appState.sessionStatus {
            errorView(message: message)
        } else {
            placeholderView(
                icon: "doc.text",
                title: "No notes generated yet",
                detail: nil
            )
        }
    }

    // MARK: - Polishing Progress

    private var polishingProgressView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: NoteVConfig.Design.accent))
                .scaleEffect(1.5)

            Text("Polishing Transcript...")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(NoteVConfig.Design.textPrimary)

            if let session = appState.currentSession {
                Text("Cleaning up \(session.transcriptSegments.filter { $0.isFinal }.count) segments")
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

            Spacer()
        }
    }

    // MARK: - Notes Generating Progress

    private var notesGeneratingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: NoteVConfig.Design.accent))
                .scaleEffect(1.5)

            Text(appState.sessionStatus == .polishing
                 ? "Polishing transcript first..."
                 : "Generating AI Notes...")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(NoteVConfig.Design.textPrimary)

            if let session = appState.currentSession {
                Text("Analyzing \(session.frames.count) frames and \(session.transcriptSegments.count) segments")
                    .font(.subheadline)
                    .foregroundColor(NoteVConfig.Design.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

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

            Spacer()
        }
    }

    // MARK: - Raw Transcript Fallback

    private func rawTranscriptFallback(showErrorBanner: Bool) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                Text(showErrorBanner
                     ? "Transcript polishing failed — showing raw transcript"
                     : "Raw transcript")
                    .font(.caption)
                    .foregroundColor(showErrorBanner ? .orange : NoteVConfig.Design.textSecondary)
                    .padding(.horizontal, NoteVConfig.Design.padding)
                    .padding(.top, 8)

                if !rawSegments.isEmpty {
                    ForEach(rawSegments) { segment in
                        HStack(alignment: .top, spacing: 8) {
                            Text(formatTimestamp(segment.startTime))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundColor(NoteVConfig.Design.textSecondary)
                                .frame(width: 40, alignment: .trailing)

                            Text(segment.text)
                                .font(.body)
                                .foregroundColor(NoteVConfig.Design.textPrimary)
                        }
                        .padding(.horizontal, NoteVConfig.Design.padding)
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Generation Failed")
                .font(.headline)
                .foregroundColor(NoteVConfig.Design.textPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundColor(NoteVConfig.Design.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

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

                Button(action: { retryGeneration() }) {
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
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Placeholder

    private func placeholderView(icon: String, title: String, detail: String?) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(NoteVConfig.Design.textSecondary)

            Text(title)
                .font(.headline)
                .foregroundColor(NoteVConfig.Design.textSecondary)

            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(NoteVConfig.Design.textSecondary.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 16) {
            // Share text (only when notes available)
            if let notes = appState.generatedNotes {
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

                // PDF
                if let url = currentPDFURL(for: notes) {
                    ShareLink(item: url) {
                        pdfButtonLabel
                    }
                } else {
                    Button(action: { generatePDF(notes: notes) }) {
                        pdfButtonLabel
                    }
                }
            }

            Spacer()

            // Done
            Button(action: {
                if isBrowsingPastSession {
                    // Pop back to session list
                    if !appState.navigationPath.isEmpty {
                        appState.navigationPath.removeLast()
                    }
                } else {
                    // Fresh recording — go home
                    appState.navigationPath = NavigationPath()
                    appState.reset()
                }
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

    private var pdfButtonLabel: some View {
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

    // MARK: - Actions

    private func retryGeneration() {
        guard let session = appState.currentSession else { return }
        NSLog("[SessionResultView] Retrying generation pipeline")
        invalidatePDFCache()
        appState.sessionStatus = .polishing

        Task {
            do {
                var updated = session

                // Re-polish
                if NoteVConfig.TranscriptPolishing.enabled {
                    let polisher = TranscriptPolisher()
                    let polished = try await polisher.polish(session: session)
                    updated.polishedTranscript = polished
                    appState.currentSession = updated
                }

                // Generate notes
                appState.sessionStatus = .generatingNotes
                let generator = NoteGenerator()
                let notes = try await generator.generateNotes(from: updated)
                appState.generatedNotes = notes

                updated.metadata.title = notes.title
                updated.notes = notes
                appState.currentSession = updated
                try SessionStore().save(session: updated)

                appState.sessionStatus = .complete
                NSLog("[SessionResultView] Retry succeeded")
            } catch {
                NSLog("[SessionResultView] Retry failed: \(error.localizedDescription)")
                appState.sessionStatus = .error(error.localizedDescription)
            }
        }
    }

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
            NSLog("[SessionResultView] PDF generated: \(tempURL.lastPathComponent), \(data.count) bytes")
        } catch {
            NSLog("[SessionResultView] ERROR writing PDF: \(error.localizedDescription)")
            invalidatePDFCache()
        }
    }

    // MARK: - Helpers

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", minutes, secs)
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
        SessionResultView()
            .environmentObject(AppState())
    }
}
