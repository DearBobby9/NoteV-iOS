import Foundation

// MARK: - CourseStore

/// JSON file persistence for courses. Same pattern as SessionStore.
final class CourseStore {

    private let fileManager = FileManager.default

    private var coursesFileURL: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("notev_courses.json")
    }

    // MARK: - Load

    func loadAll() -> [Course] {
        guard fileManager.fileExists(atPath: coursesFileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: coursesFileURL)
            let courses = try JSONDecoder().decode([Course].self, from: data)
            NSLog("[CourseStore] Loaded \(courses.count) courses")
            return courses
        } catch {
            NSLog("[CourseStore] ERROR loading courses: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Save

    func save(_ courses: [Course]) {
        do {
            let data = try JSONEncoder().encode(courses)
            try data.write(to: coursesFileURL, options: .atomic)
            NSLog("[CourseStore] Saved \(courses.count) courses")
        } catch {
            NSLog("[CourseStore] ERROR saving courses: \(error.localizedDescription)")
        }
    }

    // MARK: - CRUD

    func add(_ course: Course) {
        var courses = loadAll()
        courses.append(course)
        save(courses)
    }

    func update(_ course: Course) {
        var courses = loadAll()
        if let index = courses.firstIndex(where: { $0.id == course.id }) {
            courses[index] = course
            save(courses)
        }
    }

    func delete(id: UUID) {
        var courses = loadAll()
        courses.removeAll { $0.id == id }
        save(courses)
    }
}
