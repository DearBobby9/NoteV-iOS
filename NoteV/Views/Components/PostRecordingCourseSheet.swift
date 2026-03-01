import SwiftUI

// MARK: - PostRecordingCourseSheet

/// Bottom sheet presented after recording ends if no course was auto-detected.
/// Shows course list for manual selection or option to skip.
struct PostRecordingCourseSheet: View {
    let courses: [Course]
    var onSelect: ((Course) -> Void)?
    var onSkip: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                NoteVConfig.Design.background
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "book.circle")
                            .font(.system(size: 40))
                            .foregroundColor(NoteVConfig.Design.accent)

                        Text("Which class was this?")
                            .font(.headline)
                            .foregroundColor(NoteVConfig.Design.textPrimary)

                        Text("Tag this recording with a course")
                            .font(.subheadline)
                            .foregroundColor(NoteVConfig.Design.textSecondary)
                    }
                    .padding(.top, 20)

                    // Course list
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(courses) { course in
                                Button(action: {
                                    onSelect?(course)
                                    dismiss()
                                }) {
                                    HStack {
                                        CourseBadge(name: course.shortName, colorHex: course.color)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(course.name)
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(NoteVConfig.Design.textPrimary)

                                            if let prof = course.professor {
                                                Text(prof)
                                                    .font(.caption)
                                                    .foregroundColor(NoteVConfig.Design.textSecondary)
                                            }
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(NoteVConfig.Design.textSecondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(NoteVConfig.Design.surface)
                                    .cornerRadius(NoteVConfig.Design.cornerRadius)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, NoteVConfig.Design.padding)
                    }

                    // Skip button
                    Button(action: {
                        onSkip?()
                        dismiss()
                    }) {
                        Text("Skip")
                            .font(.callout)
                            .foregroundColor(NoteVConfig.Design.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .padding(.horizontal, NoteVConfig.Design.padding)
                    .padding(.bottom, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium])
    }
}
