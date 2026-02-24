import SwiftUI

// MARK: - FrameThumbnailView

/// Displays the most recently captured frame as a thumbnail.
struct FrameThumbnailView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: NoteVConfig.Design.cornerRadius)
                .fill(NoteVConfig.Design.surface)

            if let imageData = appState.latestFrameData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(NoteVConfig.Design.cornerRadius)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 32))
                        .foregroundColor(NoteVConfig.Design.textSecondary)

                    Text(appState.frameCount > 0 ? "Capturing frames..." : "Waiting for first frame...")
                        .font(.caption)
                        .foregroundColor(NoteVConfig.Design.textSecondary)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    FrameThumbnailView()
        .frame(height: 120)
        .padding()
        .background(NoteVConfig.Design.background)
        .environmentObject(AppState())
}
