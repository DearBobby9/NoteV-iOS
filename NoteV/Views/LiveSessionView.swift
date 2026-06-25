import SwiftUI

// MARK: - LiveSessionView

/// Active recording screen: timer, live transcript, frame thumbnails, bookmark indicator.
struct LiveSessionView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var sessionRecorder: SessionRecorder
    @Environment(\.scenePhase) private var scenePhase

    @State private var isEndingSession = false
    private let courseDetector = CourseDetector()
    private let courseStore = CourseStore()

    var body: some View {
        ZStack {
            NoteVConfig.Design.background
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Recording Header
                HStack {
                    // Recording indicator with pulse
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Circle()
                                    .fill(Color.red.opacity(0.4))
                                    .frame(width: 20, height: 20)
                                    .scaleEffect(appState.isRecording ? 1.5 : 1.0)
                                    .opacity(appState.isRecording ? 0.0 : 0.6)
                                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false), value: appState.isRecording)
                            )

                        Text("Recording")
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(.red)
                    }

                    Spacer()

                    // Timer
                    Text(appState.formattedElapsedTime)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(NoteVConfig.Design.textPrimary)
                        .monospacedDigit()

                    Spacer()

                    // Stats
                    HStack(spacing: 12) {
                        Label("\(appState.frameCount)", systemImage: "photo")
                        Label("\(appState.bookmarkCount)", systemImage: "bookmark.fill")
                        if appState.autoBookmarkCount > 0 {
                            Label("\(appState.autoBookmarkCount)", systemImage: "sparkles")
                                .foregroundColor(NoteVConfig.Design.accent)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(NoteVConfig.Design.textSecondary)
                }
                .padding(.horizontal, NoteVConfig.Design.padding)

                // Course badge (if detected)
                if let courseName = appState.currentSession?.courseName {
                    CourseBadge(name: courseName, colorHex: "#00E5FF")
                        .padding(.horizontal, NoteVConfig.Design.padding)
                }

                if let audioWarning = appState.audioSourceWarning {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.slash")
                            .foregroundColor(.orange)
                        Text(audioWarning)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(NoteVConfig.Design.cornerRadius)
                    .padding(.horizontal, NoteVConfig.Design.padding)
                }

                if let transcriptWarning = appState.liveTranscriptWarning {
                    HStack(spacing: 8) {
                        Image(systemName: "text.bubble")
                            .foregroundColor(.orange)
                        Text(transcriptWarning)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(NoteVConfig.Design.cornerRadius)
                    .padding(.horizontal, NoteVConfig.Design.padding)
                }

                GeometryReader { geometry in
                    let transcriptHeight = geometry.size.height * 0.5
                    let bookmarkControlsHeight: CGFloat = 88
                    let videoHeight = max(0, geometry.size.height - transcriptHeight - bookmarkControlsHeight)

                    VStack(spacing: 12) {
                        FrameThumbnailView()
                            .frame(height: videoHeight)
                            .padding(.horizontal, NoteVConfig.Design.padding)

                        BookmarkIndicator()
                            .frame(height: 40)

                        Button(action: {
                            triggerManualBookmark()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "bookmark.fill")
                                Text("Bookmark")
                            }
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(NoteVConfig.Design.bookmarkHighlight)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(NoteVConfig.Design.bookmarkHighlight.opacity(0.15))
                            .cornerRadius(20)
                        }

                        TranscriptScrollView()
                            .frame(height: transcriptHeight)
                            .padding(.horizontal, NoteVConfig.Design.padding)
                    }
                }
                .frame(maxHeight: .infinity)

                // End Session Button
                Button(action: {
                    endSession()
                }) {
                    if isEndingSession {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.red.opacity(0.5))
                            .cornerRadius(NoteVConfig.Design.cornerRadius)
                    } else {
                        Text("End Class")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.red.opacity(0.8))
                            .cornerRadius(NoteVConfig.Design.cornerRadius)
                    }
                }
                .disabled(isEndingSession)
                .padding(.horizontal, NoteVConfig.Design.padding)
                .padding(.bottom, 20)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background, appState.isRecording else { return }
            Task {
                await BackgroundTaskCoordinator.run(named: "NoteV.RecordingBackground") {
                    await sessionRecorder.flushRecordingPipeline()
                    await MainActor.run {
                        sessionRecorder.saveRecordingCheckpoint()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func endSession() {
        NSLog("[LiveSessionView] End Class tapped")
        isEndingSession = true

        Task {
            var session = await sessionRecorder.stopRecording()

            // Auto-detect course
            let courses = courseStore.loadAll()
            if let detected = courseDetector.detectCourse(courses: courses) {
                session.courseId = detected.id
                session.courseName = detected.shortName
                NSLog("[LiveSessionView] Auto-detected course: \(detected.name)")
            }

            appState.currentSession = session
            appState.processingWarnings = []
            appState.sessionStatus = .finalizing

            let needsCourseSelection = session.courseId == nil && !courses.isEmpty
            appState.transitionToSessionResult(needsCourseSelection: needsCourseSelection)
            isEndingSession = false

            PostProcessingOrchestrator.shared.scheduleProcessing(
                session: session,
                appState: appState,
                fromStage: .finalizing
            )
        }
    }

    private func triggerManualBookmark() {
        NSLog("[LiveSessionView] Manual bookmark triggered")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await sessionRecorder.triggerManualBookmark()
        }
    }
}

// MARK: - Preview

#Preview {
    LiveSessionView()
        .environmentObject(AppState())
        .environmentObject(SessionRecorder())
}
