import SwiftUI

// MARK: - BookmarkIndicator

/// Visual indicator when a bookmark is triggered (toast/animation).
/// TODO: Phase 2 — Animate on bookmark event, show context
struct BookmarkIndicator: View {
    @EnvironmentObject var appState: AppState
    @State private var isVisible = false

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
            // Show indicator briefly on new bookmark
            isVisible = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                isVisible = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    BookmarkIndicator()
        .environmentObject(AppState())
        .background(NoteVConfig.Design.background)
}
