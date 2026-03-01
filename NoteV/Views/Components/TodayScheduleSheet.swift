import SwiftUI

// MARK: - TodayScheduleSheet

/// Weekly calendar view showing all courses as blocks on a Mon-Fri (or Mon-Sun) grid.
/// Red horizontal line indicates current time. Today's column is highlighted.
struct TodayScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var courses: [Course] = []
    @State private var showCourseSetup = false
    @State private var currentMinute: Int = 0
    private let courseStore = CourseStore()
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    // Layout constants
    private let hourHeight: CGFloat = 60
    private let timeColumnWidth: CGFloat = 44
    private let headerHeight: CGFloat = 50

    var body: some View {
        NavigationStack {
            ZStack {
                NoteVConfig.Design.background
                    .ignoresSafeArea()

                if courses.isEmpty {
                    emptyState
                } else {
                    weeklyCalendar
                }
            }
            .navigationTitle("Weekly Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showCourseSetup = true }) {
                        Image(systemName: "pencil.and.list.clipboard")
                            .foregroundColor(NoteVConfig.Design.textSecondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(NoteVConfig.Design.accent)
                }
            }
            .navigationDestination(isPresented: $showCourseSetup) {
                CourseSetupView()
            }
        }
        .onAppear {
            courses = courseStore.loadAll()
            updateCurrentMinute()
        }
        .onChange(of: showCourseSetup) { _, isShowing in
            if !isShowing { courses = courseStore.loadAll() }
        }
        .onReceive(timer) { _ in updateCurrentMinute() }
    }

    // MARK: - Computed Properties

    /// Days to display (Mon-Fri, extend to Sun if weekend courses exist)
    private var displayDays: [Int] {
        let allDays = Set(courses.flatMap(\.schedule).map(\.dayOfWeek))
        let hasWeekend = allDays.contains(1) || allDays.contains(7)
        // dayOfWeek: 1=Sun, 2=Mon, ... 7=Sat
        if hasWeekend {
            return [2, 3, 4, 5, 6, 7, 1] // Mon-Sun
        }
        return [2, 3, 4, 5, 6] // Mon-Fri
    }

    /// All schedule entries flattened with their course
    private var allEntries: [(course: Course, entry: CourseScheduleEntry)] {
        courses.flatMap { course in
            course.schedule.map { (course, $0) }
        }
    }

    /// Hour range to display (earliest - 1 to latest + 1, clamped)
    private var hourRange: ClosedRange<Int> {
        let entries = courses.flatMap(\.schedule)
        guard !entries.isEmpty else { return 8...18 }
        let earliest = entries.map(\.startHour).min() ?? 8
        let latest = entries.map(\.endHour).max() ?? 18
        return max(0, earliest - 1)...min(23, latest + 1)
    }

    private var todayWeekday: Int {
        Calendar.current.component(.weekday, from: Date())
    }

    // MARK: - Weekly Calendar

    private var weeklyCalendar: some View {
        GeometryReader { geo in
            let dayWidth = (geo.size.width - timeColumnWidth) / CGFloat(displayDays.count)
            let totalHeight = CGFloat(hourRange.count) * hourHeight

            VStack(spacing: 0) {
                // Day header row
                dayHeaderRow(dayWidth: dayWidth)

                Divider().background(NoteVConfig.Design.textSecondary.opacity(0.3))

                // Scrollable grid
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            // Hour grid lines
                            hourGridLines(totalHeight: totalHeight, dayWidth: dayWidth)

                            // Course blocks
                            ForEach(Array(allEntries.enumerated()), id: \.offset) { _, item in
                                courseBlock(
                                    course: item.course,
                                    entry: item.entry,
                                    dayWidth: dayWidth
                                )
                            }

                            // Red NOW line (only if current time is within hour range)
                            if isCurrentTimeVisible {
                                nowLine(dayWidth: dayWidth)
                            }

                            // Invisible anchor for scroll-to
                            Color.clear
                                .frame(width: 1, height: 1)
                                .offset(y: yOffset(forMinute: currentMinute) - 80)
                                .id("nowAnchor")
                        }
                        .frame(width: geo.size.width, height: totalHeight)
                    }
                    .onAppear {
                        if isCurrentTimeVisible {
                            proxy.scrollTo("nowAnchor", anchor: .top)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Day Header

    private func dayHeaderRow(dayWidth: CGFloat) -> some View {
        let cal = Calendar.current
        let today = Date()
        let todayDay = cal.component(.day, from: today)

        // Get dates for this week
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!

        return HStack(spacing: 0) {
            // Time column spacer
            Color.clear.frame(width: timeColumnWidth, height: headerHeight)

            ForEach(displayDays, id: \.self) { dayOfWeek in
                let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
                let isToday = dayOfWeek == todayWeekday

                // Calculate the date for this weekday
                let daysFromSunday = dayOfWeek - 1
                let dayDate = cal.date(byAdding: .day, value: daysFromSunday, to: weekStart) ?? today
                let dayNumber = cal.component(.day, from: dayDate)

                VStack(spacing: 4) {
                    Text(dayNames[dayOfWeek])
                        .font(.caption2)
                        .foregroundColor(isToday ? NoteVConfig.Design.accent : NoteVConfig.Design.textSecondary)

                    Text("\(dayNumber)")
                        .font(.caption.weight(isToday ? .bold : .regular))
                        .foregroundColor(isToday ? .black : NoteVConfig.Design.textPrimary)
                        .frame(width: 24, height: 24)
                        .background(isToday ? NoteVConfig.Design.accent : Color.clear)
                        .clipShape(Circle())
                }
                .frame(width: dayWidth, height: headerHeight)
            }
        }
    }

    // MARK: - Hour Grid

    private func hourGridLines(totalHeight: CGFloat, dayWidth: CGFloat) -> some View {
        ForEach(Array(hourRange), id: \.self) { hour in
            let y = CGFloat(hour - hourRange.lowerBound) * hourHeight

            // Hour label
            Text(formatHourLabel(hour))
                .font(.system(size: 10))
                .foregroundColor(NoteVConfig.Design.textSecondary.opacity(0.6))
                .frame(width: timeColumnWidth - 4, alignment: .trailing)
                .offset(x: 0, y: y - 6)

            // Grid line
            Rectangle()
                .fill(NoteVConfig.Design.textSecondary.opacity(0.1))
                .frame(height: 0.5)
                .offset(x: timeColumnWidth, y: y)
        }
    }

    // MARK: - Course Block

    private func courseBlock(course: Course, entry: CourseScheduleEntry, dayWidth: CGFloat) -> some View {
        guard let dayIndex = displayDays.firstIndex(of: entry.dayOfWeek) else {
            return AnyView(EmptyView())
        }

        let startMin = entry.startHour * 60 + entry.startMinute
        let endMin = entry.endHour * 60 + entry.endMinute
        let blockHeight = max(CGFloat(endMin - startMin) / 60.0 * hourHeight, 20)
        let y = yOffset(forMinute: startMin)
        let x = timeColumnWidth + CGFloat(dayIndex) * dayWidth + 2

        let color = Color(hex: parseHex(course.color))
        let isNow = entry.dayOfWeek == todayWeekday &&
            currentMinute >= startMin && currentMinute < endMin

        return AnyView(
            VStack(alignment: .leading, spacing: 2) {
                Text(course.shortName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
                    .lineLimit(1)

                if blockHeight > 36 {
                    Text(entry.formattedTime)
                        .font(.system(size: 9))
                        .foregroundColor(color.opacity(0.7))
                        .lineLimit(1)
                }

                if blockHeight > 52, let location = course.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 9))
                        .foregroundColor(color.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .frame(width: dayWidth - 4, height: blockHeight, alignment: .topLeading)
            .background(color.opacity(isNow ? 0.35 : 0.2))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(color.opacity(isNow ? 0.8 : 0.4), lineWidth: isNow ? 1.5 : 0.5)
            )
            .offset(x: x, y: y)
        )
    }

    // MARK: - NOW Line

    private var isCurrentTimeVisible: Bool {
        let currentHour = currentMinute / 60
        return currentHour >= hourRange.lowerBound && currentHour <= hourRange.upperBound
    }

    private func nowLine(dayWidth: CGFloat) -> some View {
        let y = yOffset(forMinute: currentMinute)

        // Find today's column index
        let todayIndex = displayDays.firstIndex(of: todayWeekday)

        return ZStack(alignment: .leading) {
            // Red line across all columns
            Rectangle()
                .fill(Color.red.opacity(0.6))
                .frame(height: 1)
                .offset(x: timeColumnWidth, y: y)

            // Red dot on today's column
            if let idx = todayIndex {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .offset(
                        x: timeColumnWidth + CGFloat(idx) * dayWidth - 4,
                        y: y - 4
                    )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(NoteVConfig.Design.textSecondary)

            Text("No courses yet")
                .font(.title3.weight(.semibold))
                .foregroundColor(NoteVConfig.Design.textPrimary)

            Text("Chat with NoteV to set up your class schedule")
                .font(.callout)
                .foregroundColor(NoteVConfig.Design.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Helpers

    private func yOffset(forMinute minute: Int) -> CGFloat {
        let hourRangeStart = hourRange.lowerBound * 60
        return CGFloat(minute - hourRangeStart) / 60.0 * hourHeight
    }

    private func updateCurrentMinute() {
        let cal = Calendar.current
        let now = Date()
        currentMinute = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
    }

    private func formatHourLabel(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour < 12 { return "\(hour) AM" }
        if hour == 12 { return "12 PM" }
        return "\(hour - 12) PM"
    }

    private func parseHex(_ hex: String) -> UInt {
        let clean = hex.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&value)
        return UInt(value)
    }
}
