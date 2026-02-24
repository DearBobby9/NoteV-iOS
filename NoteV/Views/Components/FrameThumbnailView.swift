import SwiftUI

// MARK: - FrameThumbnailView

/// Displays the most recently captured frame as a thumbnail.
/// TODO: Phase 2 — Load actual frame images from ImageStore
struct FrameThumbnailView: View {

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: NoteVConfig.Design.cornerRadius)
                .fill(NoteVConfig.Design.surface)

            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 32))
                    .foregroundColor(NoteVConfig.Design.textSecondary)

                Text("Last Captured Frame")
                    .font(.caption)
                    .foregroundColor(NoteVConfig.Design.textSecondary)
            }

            // TODO: Phase 2 — Replace placeholder with actual frame image
            // if let imageData = latestFrameData,
            //    let uiImage = UIImage(data: imageData) {
            //     Image(uiImage: uiImage)
            //         .resizable()
            //         .aspectRatio(contentMode: .fit)
            //         .cornerRadius(NoteVConfig.Design.cornerRadius)
            // }
        }
    }
}

// MARK: - Preview

#Preview {
    FrameThumbnailView()
        .frame(height: 120)
        .padding()
        .background(NoteVConfig.Design.background)
}
