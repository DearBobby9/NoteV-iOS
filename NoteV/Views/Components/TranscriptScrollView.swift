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
                            let bookmarkType = bookmarkTypeForSegment(segment)

                            HStack(alignment: .top, spacing: 0) {
                                // Colored left border for bookmarked segments
                                if bookmarkType != .none {
                                    Rectangle()
                                        .fill(bookmarkType == .auto ? NoteVConfig.Design.accent : NoteVConfig.Design.bookmarkHighlight)
                                        .frame(width: 3)
                                        .padding(.trailing, 5)
                                }

                                // Timestamp or bookmark icon
                                if bookmarkType != .none {
                                    Image(systemName: bookmarkType == .auto ? "sparkles" : "bookmark.fill")
                                        .font(.caption)
                                        .foregroundColor(bookmarkType == .auto ? NoteVConfig.Design.accent : NoteVConfig.Design.bookmarkHighlight)
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
                            .padding(.horizontal, bookmarkType != .none ? 4 : 0)
                            .background(
                                bookmarkType == .auto
                                    ? NoteVConfig.Design.accent.opacity(0.12)
                                    : bookmarkType == .manual
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

    private enum SegmentBookmarkType {
        case none, manual, auto
    }

    /// Check if a segment overlaps with any bookmark timestamp.
    /// Returns .auto if the matching bookmark is an auto-bookmark, .manual for manual, .none if no match.
    private func bookmarkTypeForSegment(_ segment: TranscriptSegment) -> SegmentBookmarkType {
        // We only have timestamps in appState.bookmarkTimestamps (no source info),
        // so check auto bookmark count to infer. Recent auto-bookmarks are at the end.
        let matchingTimestamp = appState.bookmarkTimestamps.first { ts in
            ts >= segment.startTime && ts <= segment.endTime + 2.0
        }
        guard matchingTimestamp != nil else { return .none }

        // If we have autoBookmarkCount > 0 and latestAutoBookmarkPhrase is set,
        // and this is a recent segment, it might be auto. Use heuristic:
        // check if segment text contains any part of the trigger phrase.
        if let phrase = appState.latestAutoBookmarkPhrase,
           segment.text.lowercased().contains(phrase.lowercased()) {
            return .auto
        }
        return .manual
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
