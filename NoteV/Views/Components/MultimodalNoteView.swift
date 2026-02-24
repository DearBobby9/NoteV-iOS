import SwiftUI

// MARK: - MultimodalNoteView

/// Renders StructuredNotes with inline images and section navigation.
struct MultimodalNoteView: View {
    let notes: StructuredNotes
    var sessionId: UUID?

    private let imageStore = ImageStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            Text(notes.title)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(NoteVConfig.Design.textPrimary)

            // Summary
            if !notes.summary.isEmpty {
                Text(notes.summary)
                    .font(.body)
                    .foregroundColor(NoteVConfig.Design.textSecondary)
                    .padding()
                    .background(NoteVConfig.Design.surface)
                    .cornerRadius(NoteVConfig.Design.cornerRadius)
            }

            // Key Takeaways
            if !notes.keyTakeaways.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key Takeaways")
                        .font(.headline)
                        .foregroundColor(NoteVConfig.Design.accent)

                    ForEach(notes.keyTakeaways, id: \.self) { takeaway in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(NoteVConfig.Design.accent)
                                .padding(.top, 3)

                            Text(takeaway)
                                .font(.body)
                                .foregroundColor(NoteVConfig.Design.textPrimary)
                        }
                    }
                }
                .padding()
                .background(NoteVConfig.Design.surface)
                .cornerRadius(NoteVConfig.Design.cornerRadius)
            }

            // Sections
            ForEach(notes.sections.sorted { $0.order < $1.order }) { section in
                let isBookmarkSection = section.title.localizedCaseInsensitiveContains("bookmark")

                HStack(alignment: .top, spacing: 0) {
                    // Orange left border for bookmark sections
                    if isBookmarkSection {
                        Rectangle()
                            .fill(NoteVConfig.Design.bookmarkHighlight)
                            .frame(width: 3)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        // Section title
                        HStack(spacing: 6) {
                            if isBookmarkSection {
                                Image(systemName: "bookmark.fill")
                                    .foregroundColor(NoteVConfig.Design.bookmarkHighlight)
                            }
                            Text(section.title)
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(isBookmarkSection
                                    ? NoteVConfig.Design.bookmarkHighlight
                                    : NoteVConfig.Design.textPrimary)
                        }

                        Text(section.content)
                            .font(.body)
                            .foregroundColor(NoteVConfig.Design.textPrimary)
                            .lineSpacing(4)

                        // Section images
                        ForEach(section.images) { image in
                            VStack(spacing: 4) {
                                if let sid = sessionId,
                                   let imageData = imageStore.loadImage(filename: image.filename, sessionId: sid),
                                   let uiImage = UIImage(data: imageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .cornerRadius(8)
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(NoteVConfig.Design.surface)
                                        .frame(height: 200)
                                        .overlay(
                                            Image(systemName: "photo")
                                                .font(.largeTitle)
                                                .foregroundColor(NoteVConfig.Design.textSecondary)
                                        )
                                }

                                if !image.caption.isEmpty {
                                    Text(image.caption)
                                        .font(.caption)
                                        .foregroundColor(NoteVConfig.Design.textSecondary)
                                        .italic()
                                }
                            }
                        }
                    }
                    .padding(.leading, isBookmarkSection ? 12 : 0)
                }
                .padding(isBookmarkSection ? 12 : 0)
                .background(
                    isBookmarkSection
                        ? NoteVConfig.Design.bookmarkHighlight.opacity(0.12)
                        : Color.clear
                )
                .cornerRadius(isBookmarkSection ? NoteVConfig.Design.cornerRadius : 0)
            }

            // Generation info
            HStack {
                Spacer()
                Text("Generated by \(notes.modelUsed) via NoteV")
                    .font(.caption2)
                    .foregroundColor(NoteVConfig.Design.textSecondary)
            }
            .padding(.top, 20)
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        MultimodalNoteView(notes: StructuredNotes(
            title: "Sample Lecture Notes",
            summary: "This is a preview of generated notes.",
            sections: [
                NoteSection(title: "Introduction", content: "Sample content here...", order: 0)
            ],
            keyTakeaways: ["First key point", "Second key point"]
        ))
        .padding()
    }
    .background(NoteVConfig.Design.background)
}
