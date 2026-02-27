import SwiftUI

// MARK: - TimelineTOCSheet

/// Table of Contents sheet for quick navigation between timeline sections.
struct TimelineTOCSheet: View {
    let sections: [NoteSection]
    let onSelect: (NoteSection) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List(sections) { section in
                Button {
                    onSelect(section)
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        // Section indicator
                        if section.isBookmarkSection {
                            Image(systemName: "bookmark.fill")
                                .font(.caption)
                                .foregroundColor(NoteVConfig.Design.bookmarkHighlight)
                                .frame(width: 20)
                        } else {
                            Circle()
                                .fill(NoteVConfig.Design.accent)
                                .frame(width: 8, height: 8)
                                .frame(width: 20)
                        }

                        // Title + time range
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                                .font(.body)
                                .foregroundColor(section.isBookmarkSection
                                    ? NoteVConfig.Design.bookmarkHighlight
                                    : NoteVConfig.Design.textPrimary)
                            if let range = section.formattedTimeRange {
                                Text(range)
                                    .font(.caption)
                                    .foregroundColor(NoteVConfig.Design.textSecondary)
                                    .monospacedDigit()
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(NoteVConfig.Design.textSecondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(NoteVConfig.Design.background)
            .navigationTitle("Sections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(NoteVConfig.Design.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Preview

#Preview {
    Color.black
        .sheet(isPresented: .constant(true)) {
            TimelineTOCSheet(
                sections: [
                    NoteSection(title: "Introduction", content: "", order: 0, startTime: 0, endTime: 120),
                    NoteSection(title: "Main Topic", content: "", order: 1, startTime: 120, endTime: 450),
                    NoteSection(title: "Bookmarked Highlights", content: "", order: 2, startTime: 300, endTime: 360, isBookmarkSection: true),
                    NoteSection(title: "Conclusion", content: "", order: 3, startTime: 450, endTime: 600)
                ],
                onSelect: { _ in }
            )
        }
}
