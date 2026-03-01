import SwiftUI

// MARK: - CourseSetupView

/// Course management screen: view existing courses, add new ones via AI chat.
struct CourseSetupView: View {
    @State private var courses: [Course] = []
    @State private var showAddCourse = false
    @State private var showChat = false
    @Environment(\.dismiss) private var dismiss

    private let courseStore = CourseStore()

    var body: some View {
        ZStack {
            NoteVConfig.Design.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if courses.isEmpty {
                    emptyState
                } else {
                    courseList
                }

                // Add course button
                addCourseButton
            }
        }
        .navigationTitle("My Courses")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            courses = courseStore.loadAll()
        }
        .sheet(isPresented: $showChat) {
            ChatView(
                conversationId: ChatStore.shared.getOrCreateConversation().id,
                sessionContext: nil
            )
        }
        .onChange(of: showChat) { _, isShowing in
            // Reload courses when chat is dismissed (may have added courses via chat)
            if !isShowing {
                courses = courseStore.loadAll()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "book.closed.circle")
                .font(.system(size: 56))
                .foregroundColor(NoteVConfig.Design.textSecondary.opacity(0.5))

            Text("No courses yet")
                .font(.headline)
                .foregroundColor(NoteVConfig.Design.textSecondary)

            Text("Add your courses to auto-detect which class you're in when recording")
                .font(.subheadline)
                .foregroundColor(NoteVConfig.Design.textSecondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: - Course List

    private var courseList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(courses) { course in
                    courseCard(course)
                }
            }
            .padding(.horizontal, NoteVConfig.Design.padding)
            .padding(.vertical, 12)
        }
    }

    private func courseCard(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CourseBadge(name: course.shortName, colorHex: course.color)

                Text(course.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(NoteVConfig.Design.textPrimary)

                Spacer()

                // Delete button
                Button(action: {
                    deleteCourse(course)
                }) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(NoteVConfig.Design.textSecondary)
                }
            }

            if let professor = course.professor {
                HStack(spacing: 4) {
                    Image(systemName: "person")
                    Text(professor)
                }
                .font(.caption)
                .foregroundColor(NoteVConfig.Design.textSecondary)
            }

            if !course.schedule.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text(scheduleText(course.schedule))
                }
                .font(.caption)
                .foregroundColor(NoteVConfig.Design.textSecondary)
            }

            if let location = course.location {
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                    Text(location)
                }
                .font(.caption)
                .foregroundColor(NoteVConfig.Design.textSecondary)
            }
        }
        .padding(12)
        .background(NoteVConfig.Design.surface)
        .cornerRadius(NoteVConfig.Design.cornerRadius)
    }

    // MARK: - Add Course Button

    private var addCourseButton: some View {
        Button(action: { showChat = true }) {
            HStack {
                Image(systemName: "sparkles")
                Text("Add via Chat")
            }
            .font(.headline)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(NoteVConfig.Design.accent)
            .cornerRadius(NoteVConfig.Design.cornerRadius)
        }
        .padding(.horizontal, NoteVConfig.Design.padding)
        .padding(.vertical, 12)
        .background(NoteVConfig.Design.background)
    }

    // MARK: - Helpers

    private func deleteCourse(_ course: Course) {
        courseStore.delete(id: course.id)
        courses.removeAll { $0.id == course.id }
    }

    private func scheduleText(_ entries: [CourseScheduleEntry]) -> String {
        let days = entries.map(\.dayName).joined(separator: "/")
        if let first = entries.first {
            return "\(days) \(first.formattedTime)"
        }
        return days
    }
}
