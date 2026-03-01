import Foundation

// MARK: - CourseDetector

/// Detects which course is currently happening based on time and schedule.
/// Pure Calendar/DateComponents logic — no external dependencies.
final class CourseDetector {

    /// Detect the course matching the given date based on schedule entries.
    /// Match if: startTime - earlyWindow <= now <= startTime + lateWindow.
    /// For back-to-back courses, picks the one with closest startTime.
    func detectCourse(at date: Date = Date(), courses: [Course]) -> Course? {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date) // 1=Sun ... 7=Sat
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let nowMinutes = hour * 60 + minute

        let earlyWindow = NoteVConfig.CourseSetup.earlyWindowMinutes
        let lateWindow = NoteVConfig.CourseSetup.lateWindowMinutes

        var bestMatch: (course: Course, distance: Int)?

        for course in courses {
            for entry in course.schedule {
                guard entry.dayOfWeek == weekday else { continue }

                let startMinutes = entry.startHour * 60 + entry.startMinute
                let earlyBound = startMinutes - earlyWindow
                let lateBound = startMinutes + lateWindow

                guard nowMinutes >= earlyBound && nowMinutes <= lateBound else { continue }

                let distance = abs(nowMinutes - startMinutes)
                if bestMatch == nil || distance < bestMatch!.distance {
                    bestMatch = (course, distance)
                }
            }
        }

        if let match = bestMatch {
            NSLog("[CourseDetector] Detected course: \(match.course.name) (distance: \(match.distance) min)")
            return match.course
        }

        NSLog("[CourseDetector] No course detected for weekday \(weekday) at \(hour):\(String(format: "%02d", minute))")
        return nil
    }
}
