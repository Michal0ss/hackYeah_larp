import Foundation

/// Reading a plan by date. A dated plan holds every session of the whole plan; the coach and the change logic look at
/// a window of seven days, where each weekday occurs once. A plan without dates (a weekly pattern, sample data) is
/// its own window, so everything below also works on it.
public extension TrainingPlan {
    /// Weeks start on Monday, as in the plan's `weekday`.
    static var calendar: Calendar { Calendar(identifier: .iso8601) }

    /// True when every session has a date.
    var isDated: Bool { !sessions.isEmpty && sessions.allSatisfy { $0.date != nil } }

    /// The sessions in the order they happen: by date, then by weekday.
    var chronological: [PlannedSession] {
        sessions.sorted {
            if let a = $0.date, let b = $1.date, a != b { return a < b }
            return $0.weekday < $1.weekday
        }
    }

    /// The day of the last session of a dated plan.
    var lastSessionDate: Date? { sessions.compactMap(\.date).max() }

    /// The sessions of the seven days from `day` on (`day` included), in order.
    func window(from day: Date, calendar: Calendar = TrainingPlan.calendar) -> [PlannedSession] {
        guard isDated else { return chronological }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return [] }
        return chronological.filter { ($0.date ?? start) >= start && ($0.date ?? end) < end }
    }

    /// The sessions of the calendar week (Monday to Sunday) that contains `day`.
    func week(containing day: Date, calendar: Calendar = TrainingPlan.calendar) -> [PlannedSession] {
        guard isDated else { return chronological }
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: day) else { return [] }
        return chronological.filter { interval.contains($0.date ?? .distantPast) }
    }

    /// The session planned for `day`.
    func session(on day: Date, calendar: Calendar = TrainingPlan.calendar) -> PlannedSession? {
        if isDated { return sessions.first { $0.date.map { calendar.isDate($0, inSameDayAs: day) } ?? false } }
        return sessions.first { $0.weekday == TrainingPlan.isoWeekday(of: day, calendar: calendar) }
    }

    /// The session of `day`, or the next one after it. Nil when the plan has run out.
    func sessionOnOrAfter(_ day: Date, calendar: Calendar = TrainingPlan.calendar) -> PlannedSession? {
        if let today = session(on: day, calendar: calendar) { return today }
        let start = calendar.startOfDay(for: day)
        if isDated { return chronological.first { ($0.date ?? .distantPast) > start } }
        let weekday = TrainingPlan.isoWeekday(of: day, calendar: calendar)
        return chronological.first { $0.weekday > weekday } ?? chronological.first
    }

    /// True when the plan has dates and its last session is before `day`.
    func hasEnded(on day: Date, calendar: Calendar = TrainingPlan.calendar) -> Bool {
        guard isDated, let last = lastSessionDate else { return false }
        return calendar.startOfDay(for: last) < calendar.startOfDay(for: day)
    }

    /// How many sessions a week has: counted over the first seven days of the plan.
    var sessionsPerWeek: Int {
        guard isDated, let first = sessions.compactMap(\.date).min() else { return sessions.count }
        return window(from: first).count
    }

    /// 1 = Monday ... 7 = Sunday.
    static func isoWeekday(of date: Date, calendar: Calendar = TrainingPlan.calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }
}
