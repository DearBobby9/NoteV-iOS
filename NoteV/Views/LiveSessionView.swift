import SwiftUI

// MARK: - LiveSessionView

/// Active recording screen: timer, live transcript, frame thumbnails, bookmark indicator.
struct LiveSessionView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var sessionRecorder: SessionRecorder

    @State private var isEndingSession = false
    @State private var showCourseSheet = false
    @State private var pendingSession: SessionData?
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

                // Frame Thumbnail Area
                FrameThumbnailView()
                    .frame(height: 120)
                    .padding(.horizontal, NoteVConfig.Design.padding)

                // Bookmark Indicator
                BookmarkIndicator()
                    .frame(height: 40)

                // Manual Bookmark Button
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

                // Transcript
                TranscriptScrollView()
                    .padding(.horizontal, NoteVConfig.Design.padding)

                Spacer()

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
        .sheet(isPresented: $showCourseSheet) {
            PostRecordingCourseSheet(
                courses: courseStore.loadAll(),
                onSelect: { course in
                    tagSessionWithCourse(course)
                },
                onSkip: {
                    // Continue without course tag
                }
            )
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
            appState.sessionStatus = .polishing

            // Navigate to session result
            appState.navigationPath.append(NavigationDestination.sessionResult)
            isEndingSession = false

            // Show course selection sheet if no auto-detection and courses exist
            if session.courseId == nil && !courses.isEmpty {
                showCourseSheet = true
            }

            Task {
                _ = await PostProcessingOrchestrator.shared.process(
                    session: session,
                    appState: appState,
                    fromStage: .polishing
                )
            }
        }
    }

    private func tagSessionWithCourse(_ course: Course) {
        if var session = appState.currentSession {
            session.courseId = course.id
            session.courseName = course.shortName
            appState.currentSession = session
            NSLog("[LiveSessionView] Tagged session with course: \(course.name)")
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
