import SwiftUI

// MARK: - BookmarkIndicator

/// Visual indicator when a bookmark is triggered (toast/animation).
/// TODO: Phase 2 — Animate on bookmark event, show context
struct BookmarkIndicator: View {
    @EnvironmentObject var appState: AppState
    @State private var isVisible = false
    @State private var isAutoBookmark = false
    @State private var autoPhrase: String?
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            if isVisible {
                HStack(spacing: 8) {
                    Image(systemName: isAutoBookmark ? "sparkles" : "bookmark.fill")
                        .foregroundColor(isAutoBookmark ? NoteVConfig.Design.accent : NoteVConfig.Design.bookmarkHighlight)

                    if isAutoBookmark, let phrase = autoPhrase {
                        Text("Important: '\(phrase)'")
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(NoteVConfig.Design.accent)
                            .lineLimit(1)
                    } else {
                        Text("Bookmarked!")
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(NoteVConfig.Design.bookmarkHighlight)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    (isAutoBookmark ? NoteVConfig.Design.accent : NoteVConfig.Design.bookmarkHighlight).opacity(0.15)
                )
                .cornerRadius(20)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: isVisible)
        .onChange(of: appState.bookmarkCount) { _, _ in
            showToast(auto: false, phrase: nil)
        }
        .onChange(of: appState.autoBookmarkCount) { _, _ in
            showToast(auto: true, phrase: appState.latestAutoBookmarkPhrase)
        }
        .onDisappear {
            hideTask?.cancel()
            hideTask = nil
            isVisible = false
        }
    }

    private func showToast(auto: Bool, phrase: String?) {
        hideTask?.cancel()
        isAutoBookmark = auto
        autoPhrase = phrase
        isVisible = true
        let duration: UInt64 = auto ? 3_000_000_000 : 2_000_000_000
        hideTask = Task {
            try? await Task.sleep(nanoseconds: duration)
            guard !Task.isCancelled else { return }
            isVisible = false
        }
    }
}

// MARK: - Preview

#Preview {
    BookmarkIndicator()
        .environmentObject(AppState())
        .background(NoteVConfig.Design.background)
}
