import SwiftUI

// MARK: - LiveSessionView

/// Active recording screen: timer, live transcript, frame thumbnails, bookmark indicator.
/// TODO: Phase 2 — Wire up live data streams
struct LiveSessionView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            NoteVConfig.Design.background
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Recording Header
                HStack {
                    // Recording indicator
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 12, height: 12)

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
                    }
                    .font(.caption)
                    .foregroundColor(NoteVConfig.Design.textSecondary)
                }
                .padding(.horizontal, NoteVConfig.Design.padding)

                // Frame Thumbnail Area
                FrameThumbnailView()
                    .frame(height: 120)
                    .padding(.horizontal, NoteVConfig.Design.padding)

                // Bookmark Indicator
                BookmarkIndicator()
                    .frame(height: 40)

                // Transcript
                TranscriptScrollView()
                    .padding(.horizontal, NoteVConfig.Design.padding)

                Spacer()

                // End Session Button
                Button(action: {
                    NSLog("[LiveSessionView] End Class tapped")
                    // TODO: Phase 2 — Stop recording, navigate to NotesResultView
                }) {
                    Text("End Class")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(NoteVConfig.Design.cornerRadius)
                }
                .padding(.horizontal, NoteVConfig.Design.padding)
                .padding(.bottom, 20)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Preview

#Preview {
    LiveSessionView()
        .environmentObject(AppState())
}
