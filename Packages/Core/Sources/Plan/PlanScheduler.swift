import Contracts
import Foundation

/// Turns a weekly pattern (weekday 1...7, what the backend and the templates produce) into a plan with dates: every
/// session gets the calendar day it happens on, for a number of weeks from the start day.
///
///     pattern: Mon Nogi, Wed Góra, Fri Całe ciało
///     start Thu 9.10, 8 weeks  ──►  Fri 10.10 Całe ciało, Mon 13.10 Nogi, Wed 15.10 Góra, ... up to Wed 3.12
///
/// - Each occurrence is its own session with its own id, so "done", changes and moves belong to one date.
/// - Every fourth week is lighter (one set less where there are more than two), so a long plan has a rhythm.
/// - Only sessions on or after the start day are planned; the plan ends the day before `start + weeks * 7`.
public enum PlanScheduler {
    public static let defaultWeeks = 8
    /// Every fourth week (the 4th, 8th, ...) is a lighter one.
    public static let deloadEvery = 4

    public static func schedule(_ pattern: TrainingPlan, startingOn start: Date, weeks: Int = defaultWeeks,
                                calendar: Calendar = TrainingPlan.calendar) -> TrainingPlan {
        let weeks = max(1, weeks)
        let startDay = calendar.startOfDay(for: start)
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: startDay)?.start,
              let end = calendar.date(byAdding: .day, value: weeks * 7, to: startDay) else { return pattern }

        var sessions: [PlannedSession] = []
        for week in 0...weeks {
            for template in pattern.sessions.sorted(by: { $0.weekday < $1.weekday }) {
                guard let date = calendar.date(byAdding: .day, value: week * 7 + template.weekday - 1, to: weekStart),
                      date >= startDay, date < end else { continue }
                let index = calendar.dateComponents([.day], from: startDay, to: date).day.map { $0 / 7 } ?? 0
                var session = template
                session.id = UUID()
                session.date = date
                session.status = .planned
                if (index + 1) % deloadEvery == 0 { lighten(&session) }
                sessions.append(session)
            }
        }
        var plan = pattern
        plan.sessions = sessions
        plan.startDate = startDay
        plan.weeks = weeks
        return plan
    }

    static let deloadNote = "Tydzień lżejszy: o jedną serię mniej, żeby organizm nadążył z regeneracją."

    private static func lighten(_ session: inout PlannedSession) {
        var changed = false
        for index in session.exercises.indices where session.exercises[index].sets > 2 {
            session.exercises[index].sets -= 1
            changed = true
        }
        if changed { session.adaptationNote = deloadNote }
    }
}
