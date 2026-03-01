import Foundation

// MARK: - Course

/// A course in the student's schedule.
struct Course: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var professor: String?
    var location: String?
    var schedule: [CourseScheduleEntry]
    var color: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        professor: String? = nil,
        location: String? = nil,
        schedule: [CourseScheduleEntry] = [],
        color: String = "#00E5FF",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.professor = professor
        self.location = location
        self.schedule = schedule
        self.color = color
        self.createdAt = createdAt
    }

    /// Short display name (e.g., "CS 229")
    var shortName: String {
        // Try to extract course code (letters + numbers at start)
        let words = name.split(separator: " ")
        if words.count >= 2 {
            let first = String(words[0])
            let second = String(words[1])
            if first.count <= 5 && second.allSatisfy({ $0.isNumber || $0 == "." }) {
                return "\(first) \(second)"
            }
        }
        return String(name.prefix(12))
    }
}

// MARK: - CourseScheduleEntry

/// A single time slot in a course's weekly schedule.
struct CourseScheduleEntry: Codable, Sendable {
    /// Day of week: 1=Sunday, 2=Monday, ... 7=Saturday (Calendar convention)
    let dayOfWeek: Int
    /// Start time (hour + minute only)
    let startHour: Int
    let startMinute: Int
    /// End time (hour + minute only)
    let endHour: Int
    let endMinute: Int

    /// Formatted time string (e.g., "10:00 AM - 11:15 AM")
    var formattedTime: String {
        let start = formatTime(hour: startHour, minute: startMinute)
        let end = formatTime(hour: endHour, minute: endMinute)
        return "\(start) - \(end)"
    }

    /// Day name (e.g., "Mon")
    var dayName: String {
        switch dayOfWeek {
        case 1: return "Sun"
        case 2: return "Mon"
        case 3: return "Tue"
        case 4: return "Wed"
        case 5: return "Thu"
        case 6: return "Fri"
        case 7: return "Sat"
        default: return "?"
        }
    }

    private func formatTime(hour: Int, minute: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let h = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour)
        return String(format: "%d:%02d %@", h, minute, period)
    }
}
