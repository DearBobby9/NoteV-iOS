import AVKit
import SwiftUI

// MARK: - SessionResultView

/// Post-recording view: Video replay (when available), Timeline, AI Notes, and Tasks.
struct SessionResultView: View {
    @EnvironmentObject var appState: AppState

    /// True when navigated from SessionListView (past session browsing)
    var isBrowsingPastSession: Bool = false

    @State private var selectedTab: ResultTab = .timeline
    @State private var pdfURL: URL?
    @State private var pdfSourceSessionId: UUID?
    @State private var pdfSourceGeneratedAt: Date?
    @State private var rawSegments: [TranscriptSegment] = []
    @State private var exportError: String?
    @State private var showChat = false
    @State private var showCourseSheet = false
    @State private var videoPlayer: AVPlayer?

    private let courseStore = CourseStore()

    enum ResultTab: String, CaseIterable {
        case video = "Video"
        case timeline = "Timeline"
        case aiNotes = "AI Notes"
        case tasks = "Tasks"
    }

    private let sessionStore = SessionStore()

    private var visibleTabs: [ResultTab] {
        sessionVideoURL != nil ? ResultTab.allCases : [.timeline, .aiNotes, .tasks]
    }

    private var sessionVideoURL: URL? {
        guard let session = appState.currentSession,
              session.metadata.videoFilename != nil else { return nil }
        let url = sessionStore.videoURL(for: session.id)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var body: some View {
        ZStack {
            NoteVConfig.Design.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if let warning = appState.videoRecordingWarning {
                    videoWarningBanner(warning)
                }

                ProcessingStageBanner(onCancel: cancelProcessing)

                Picker("View", selection: $selectedTab) {
                    ForEach(visibleTabs, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, NoteVConfig.Design.padding)
                .padding(.vertical, 6)

                Group {
                    switch selectedTab {
                    case .video:
                        videoContent
                    case .timeline:
                        timelineContent
                    case .aiNotes:
                        aiNotesContent
                    case .tasks:
                        tasksContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                actionBar
            }

            if appState.sessionStatus == .complete, appState.currentSession != nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { showChat = true }) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.title2)
                                .foregroundColor(.black)
                                .frame(width: 56, height: 56)
                                .background(NoteVConfig.Design.accent)
                                .cornerRadius(28)
                                .shadow(color: NoteVConfig.Design.accent.opacity(0.4), radius: 8, y: 4)
                        }
                        .padding(.trailing, NoteVConfig.Design.padding)
                        .padding(.bottom, appState.isPostProcessing ? 72 : 88)
                    }
                }
            }
        }
        .navigationTitle(appState.currentSession?.metadata.title ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: goHome) {
                    Label("Home", systemImage: "house")
                }
            }
        }
        .onAppear {
            if let session = appState.currentSession {
                rawSegments = session.transcriptSegments
                    .filter { $0.isFinal }
                    .sorted { $0.startTime < $1.startTime }
            }
            if sessionVideoURL != nil {
                selectedTab = .video
            } else if !visibleTabs.contains(selectedTab) {
                selectedTab = visibleTabs.first ?? .timeline
            }
            if !isBrowsingPastSession, appState.shouldShowCourseSelection {
                showCourseSheet = true
                appState.shouldShowCourseSelection = false
            }
        }
        .sheet(isPresented: $showCourseSheet) {
            PostRecordingCourseSheet(
                courses: courseStore.loadAll(),
                onSelect: { course in
                    tagSessionWithCourse(course)
                },
                onSkip: {}
            )
        }
        .onDisappear {
            videoPlayer?.pause()
            videoPlayer = nil
        }
        .sheet(isPresented: $showChat) {
            if let session = appState.currentSession {
                ChatView(
                    conversationId: session.metadata.sessionId,
                    sessionContext: session
                )
            }
        }
        .alert("Export Failed", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "Unknown error")
        }
    }

    // MARK: - Video Tab

    @ViewBuilder
    private var videoContent: some View {
        if let url = sessionVideoURL {
            if let player = videoPlayer {
                VideoPlayer(player: player)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .horizontal)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        videoPlayer = AVPlayer(url: url)
                    }
            }
        } else {
            placeholderView(
                icon: "video.slash",
                title: "No session video",
                detail: "Video was not recorded for this session"
            )
        }
    }

    private func videoWarningBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(NoteVConfig.Design.bookmarkHighlight)
            Text(message)
                .font(.caption)
                .foregroundColor(NoteVConfig.Design.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(NoteVConfig.Design.surface)
        .cornerRadius(NoteVConfig.Design.cornerRadius)
        .padding(.horizontal, NoteVConfig.Design.padding)
        .padding(.top, 4)
    }

    // MARK: - Timeline Tab (Layer 1)

    @ViewBuilder
    private var timelineContent: some View {
        if let transcript = appState.currentSession?.polishedTranscript, !transcript.segments.isEmpty {
            TranscriptTimelineView(
                transcript: transcript,
                sessionId: appState.currentSession?.id
            )
        } else if !rawSegments.isEmpty {
            rawTranscriptFallback(showErrorBanner: showsTranscriptWarning)
        } else if appState.isPostProcessing || appState.sessionStatus == .polishing {
            compactProcessingState
        } else if case .error = appState.sessionStatus {
            rawTranscriptFallback(showErrorBanner: true)
        } else {
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
        if let notes = appState.generatedNotes {
            TimelineNoteView(notes: notes, sessionId: appState.currentSession?.id)
        } else if case .error(let message) = appState.sessionStatus {
            errorView(message: message)
        } else if appState.isPostProcessing
                    || appState.sessionStatus == .polishing
                    || appState.sessionStatus == .generatingNotes
                    || appState.sessionStatus == .analyzingSlides {
            compactProcessingState
        } else {
            placeholderView(
                icon: "doc.text",
                title: "No notes generated yet",
                detail: nil
            )
        }
    }

    // MARK: - Tasks Tab (Layer 3)

    @ViewBuilder
    private var tasksContent: some View {
        if !appState.extractedTodos.isEmpty {
            TasksTabView(
                todos: appState.extractedTodos,
                sessionId: appState.currentSession?.id,
                sessionTitle: appState.currentSession?.metadata.title ?? "NoteV Session",
                onExportToReminders: { items in
                    exportTodosToReminders(items)
                }
            )
        } else if appState.isPostProcessing
                    || appState.sessionStatus == .polishing
                    || appState.sessionStatus == .generatingNotes
                    || appState.sessionStatus == .extractingTodos
                    || appState.sessionStatus == .analyzingSlides {
            compactProcessingState
        } else {
            placeholderView(
                icon: "checklist",
                title: "No tasks extracted",
                detail: "Action items from lectures will appear here"
            )
        }
    }

    // MARK: - Compact Processing State

    private var compactProcessingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: NoteVConfig.Design.accent))
                .scaleEffect(1.2)

            Text(appState.processingStageLabel ?? "Processing…")
                .font(.headline)
                .foregroundColor(NoteVConfig.Design.textPrimary)
                .multilineTextAlignment(.center)

            Text("You can keep browsing or go home anytime.")
                .font(.caption)
                .foregroundColor(NoteVConfig.Design.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(action: goHome) {
                    Text("Go Home")
                        .font(.callout.weight(.medium))
                        .foregroundColor(NoteVConfig.Design.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(NoteVConfig.Design.surface)
                        .cornerRadius(NoteVConfig.Design.cornerRadius)
                }

                Button(action: cancelProcessing) {
                    Text("Stop Processing")
                        .font(.callout.weight(.medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(NoteVConfig.Design.cornerRadius)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    private var showsTranscriptWarning: Bool {
        if case .error = appState.sessionStatus { return true }
        return false
    }

    // MARK: - Raw Transcript Fallback

    private func rawTranscriptFallback(showErrorBanner: Bool) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if showErrorBanner {
                    Text("Transcript polishing failed — showing raw transcript")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, NoteVConfig.Design.padding)
                        .padding(.top, 8)
                } else if appState.isPostProcessing {
                    Text("Live transcript — polishing in progress")
                        .font(.caption)
                        .foregroundColor(NoteVConfig.Design.textSecondary)
                        .padding(.horizontal, NoteVConfig.Design.padding)
                        .padding(.top, 8)
                }

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
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Button(action: goHome) {
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
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        VStack(spacing: 8) {
            if sessionVideoURL != nil
                || appState.generatedNotes != nil
                || (appState.sessionStatus == .complete && !appState.isPostProcessing) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        if let videoURL = sessionVideoURL {
                            ShareLink(item: videoURL) {
                                actionBarButton(icon: "video", label: "Export Video")
                            }
                        }

                        if let notes = appState.generatedNotes {
                            ShareLink(item: notesAsText(notes)) {
                                actionBarButton(icon: "square.and.arrow.up", label: "Share")
                            }

                            if let url = currentPDFURL(for: notes) {
                                ShareLink(item: url) {
                                    actionBarButton(icon: "doc.richtext", label: "PDF")
                                }
                            } else {
                                Button(action: { generatePDF(notes: notes) }) {
                                    actionBarButton(icon: "doc.richtext", label: "PDF")
                                }
                            }
                        }

                        if appState.sessionStatus == .complete, !appState.isPostProcessing {
                            let canReprocess = appState.currentSession.map { sessionStore.canReprocess($0) } ?? false
                            Button(action: { reprocessSession() }) {
                                actionBarButton(
                                    icon: "arrow.clockwise",
                                    label: "Reprocess",
                                    accent: canReprocess
                                )
                            }
                            .disabled(!canReprocess)
                        }
                    }
                    .padding(.horizontal, NoteVConfig.Design.padding)
                }
            }

            Button(action: goHome) {
                HStack(spacing: 8) {
                    Image(systemName: appState.isPostProcessing ? "house" : "checkmark.circle")
                    Text(appState.isPostProcessing ? "Go Home" : "Done")
                }
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(NoteVConfig.Design.accent)
                .cornerRadius(NoteVConfig.Design.cornerRadius)
            }
            .padding(.horizontal, NoteVConfig.Design.padding)
        }
        .padding(.vertical, 8)
        .background(NoteVConfig.Design.background)
    }

    private func actionBarButton(icon: String, label: String, accent: Bool = true) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(label)
                .lineLimit(1)
        }
        .font(.callout)
        .fontWeight(.medium)
        .foregroundColor(accent ? NoteVConfig.Design.accent : NoteVConfig.Design.textSecondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(NoteVConfig.Design.surface)
        .cornerRadius(NoteVConfig.Design.cornerRadius)
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Actions

    private func goHome() {
        videoPlayer?.pause()
        videoPlayer = nil

        if isBrowsingPastSession {
            if !appState.navigationPath.isEmpty {
                appState.navigationPath.removeLast()
            }
        } else if appState.isPostProcessing {
            appState.navigationPath = NavigationPath()
        } else {
            appState.navigationPath = NavigationPath()
            appState.reset()
        }
    }

    private func tagSessionWithCourse(_ course: Course) {
        if var session = appState.currentSession {
            session.courseId = course.id
            session.courseName = course.shortName
            appState.currentSession = session
            try? sessionStore.save(session: session)
            NSLog("[SessionResultView] Tagged session with course: \(course.name)")
        }
    }

    private func cancelProcessing() {
        PostProcessingOrchestrator.shared.cancelProcessing(appState: appState)
    }

    private func retryGeneration() {
        guard let session = appState.currentSession else { return }
        runPostProcessing(for: session)
    }

    private func reprocessSession() {
        guard let session = appState.currentSession else { return }
        runPostProcessing(for: session)
    }

    private func runPostProcessing(for session: SessionData) {
        guard !PostProcessingOrchestrator.shared.isProcessing else { return }
        guard sessionStore.canReprocess(session) else { return }
        NSLog("[SessionResultView] Starting post-processing pipeline")
        invalidatePDFCache()
        appState.processingWarnings = reprocessPreflightWarnings(for: session)
        appState.generatedNotes = nil
        appState.extractedTodos = []

        var cleared = session
        cleared.notes = nil
        cleared.todos = nil
        cleared.slideAnalysis = nil
        cleared.polishedTranscript = nil
        appState.currentSession = cleared

        PostProcessingOrchestrator.shared.scheduleProcessing(
            session: cleared,
            appState: appState,
            fromStage: reprocessStartStage(for: session)
        )
    }

    private func reprocessStartStage(for session: SessionData) -> PostProcessingStage {
        let videoURL = sessionStore.videoURL(for: session.id)
        let hasVideo = session.metadata.videoFilename != nil
            && FileManager.default.fileExists(atPath: videoURL.path)

        if session.transcriptSegments.isEmpty, hasVideo, NoteVConfig.TranscriptExtraction.enabled {
            return .recoveringTranscript
        }
        guard NoteVConfig.FrameExtraction.enabled, hasVideo else {
            return .polishing
        }
        return .extractingFrames
    }

    private func reprocessPreflightWarnings(for session: SessionData) -> [String] {
        guard NoteVConfig.FrameExtraction.enabled else { return [] }
        let hasVideo = session.metadata.videoFilename != nil
            && FileManager.default.fileExists(atPath: sessionStore.videoURL(for: session.id).path)
        if !hasVideo {
            return ["No video — reprocessing notes from existing frames"]
        }
        return []
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

    // MARK: - Reminders Export

    private func exportTodosToReminders(_ items: [TodoItem]) {
        Task { @MainActor in
            do {
                let service = ReminderSyncService.shared
                let granted = try await service.requestAccess()
                guard granted else {
                    NSLog("[SessionResultView] Reminders access denied")
                    exportError = "Reminders access denied. Enable in Settings > Privacy > Reminders."
                    return
                }

                let sessionTitle = appState.currentSession?.metadata.title ?? "NoteV Session"
                let sessionId = appState.currentSession?.id
                let synced = try await service.exportToReminders(items, sessionTitle: sessionTitle, sessionId: sessionId)

                // Update synced state
                var updatedTodos = appState.extractedTodos
                for syncedItem in synced {
                    if let index = updatedTodos.firstIndex(where: { $0.id == syncedItem.id }) {
                        updatedTodos[index].isSynced = syncedItem.isSynced
                        updatedTodos[index].eventKitIdentifier = syncedItem.eventKitIdentifier
                    }
                }
                appState.extractedTodos = updatedTodos

                // Persist synced state
                if var session = appState.currentSession {
                    session.todos = updatedTodos
                    appState.currentSession = session
                    try SessionStore().save(session: session)
                }

                NSLog("[SessionResultView] Exported \(synced.count) items to Reminders")
            } catch {
                NSLog("[SessionResultView] Reminders export failed: \(error.localizedDescription)")
                exportError = error.localizedDescription
            }
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
