import SwiftUI

// MARK: - BookmarkIndicator

/// Visual indicator when a bookmark is triggered (toast/animation).
/// TODO: Phase 2 — Animate on bookmark event, show context
struct BookmarkIndicator: View {
    @EnvironmentObject var appState: AppState
    @State private var isVisible = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            if isVisible {
                HStack(spacing: 8) {
                    Image(systemName: "bookmark.fill")
                        .foregroundColor(NoteVConfig.Design.bookmarkHighlight)

                    Text("Bookmarked!")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundColor(NoteVConfig.Design.bookmarkHighlight)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(NoteVConfig.Design.bookmarkHighlight.opacity(0.15))
                .cornerRadius(20)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3), value: isVisible)
        .onChange(of: appState.bookmarkCount) { _, _ in
            // Cancel previous hide timer and restart 2s window
            hideTask?.cancel()
            isVisible = true
            hideTask = Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                isVisible = false
            }
        }
        .onDisappear {
            hideTask?.cancel()
            hideTask = nil
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
