import SwiftUI

// MARK: - TranscriptScrollView

/// Scrolling display of live transcript segments.
/// TODO: Phase 2 — Auto-scroll to bottom, highlight current segment
struct TranscriptScrollView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if appState.transcriptSegments.isEmpty {
                        Text("Listening...")
                            .font(.body)
                            .foregroundColor(NoteVConfig.Design.textSecondary)
                            .italic()
                            .padding(.top, 8)
                    } else {
                        ForEach(appState.transcriptSegments) { segment in
                            let isBookmarked = appState.bookmarkTimestamps.contains { ts in
                                ts >= segment.startTime && ts <= segment.endTime + 2.0
                            }

                            HStack(alignment: .top, spacing: 0) {
                                // Orange left border for bookmarked segments
                                if isBookmarked {
                                    Rectangle()
                                        .fill(NoteVConfig.Design.bookmarkHighlight)
                                        .frame(width: 3)
                                        .padding(.trailing, 5)
                                }

                                // Timestamp or bookmark icon
                                if isBookmarked {
                                    Image(systemName: "bookmark.fill")
                                        .font(.caption)
                                        .foregroundColor(NoteVConfig.Design.bookmarkHighlight)
                                        .frame(width: 50, alignment: .trailing)
                                        .padding(.trailing, 8)
                                } else {
                                    Text(formatTimestamp(segment.startTime))
                                        .font(.caption)
                                        .foregroundColor(NoteVConfig.Design.accent)
                                        .frame(width: 50, alignment: .trailing)
                                        .padding(.trailing, 8)
                                }

                                // Text
                                Text(segment.text)
                                    .font(.body)
                                    .foregroundColor(segment.isFinal
                                        ? NoteVConfig.Design.textPrimary
                                        : NoteVConfig.Design.textSecondary)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, isBookmarked ? 4 : 0)
                            .background(
                                isBookmarked
                                    ? NoteVConfig.Design.bookmarkHighlight.opacity(0.12)
                                    : Color.clear
                            )
                            .cornerRadius(6)
                            .id(segment.id)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            .background(NoteVConfig.Design.surface)
            .cornerRadius(NoteVConfig.Design.cornerRadius)
            .onChange(of: appState.transcriptSegments.count) { _, _ in
                if let lastId = appState.transcriptSegments.last?.id {
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Preview

#Preview {
    TranscriptScrollView()
        .environmentObject(AppState())
        .frame(height: 300)
        .background(NoteVConfig.Design.background)
}
