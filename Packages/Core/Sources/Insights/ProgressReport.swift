import Foundation
import Contracts

public struct ScorePoint: Equatable, Sendable, Identifiable {
    public var id: Date { date }
    public var date: Date
    /// 0...100.
    public var score: Int

    public init(date: Date, score: Int) {
        self.date = date
        self.score = score
    }
}

public struct DayValue: Equatable, Sendable, Identifiable {
    public var id: Date { date }
    /// Start of the day.
    public var date: Date
    /// 0...100.
    public var value: Int

    public init(date: Date, value: Int) {
        self.date = date
        self.value = value
    }
}

public struct TechniqueProgress: Equatable, Sendable {
    /// Oldest first.
    public var points: [ScorePoint]
    public var latest: Int
    /// Latest minus first score.
    public var deltaFromStart: Int
    /// One or two short sentences, e.g. "Wynik rośnie od 6 analiz. Najmocniejsza strona: głębokość. Do poprawy: tułów."
    public var summary: String
}

public struct ActivityDay: Equatable, Sendable, Identifiable {
    public var id: Date { date }
    public var date: Date
    /// Nil for a day after today, so a calendar grid stays a full rectangle of whole weeks without
    /// claiming data for the future. 0 or more for a real day (0 = no set logged).
    public var setCount: Int?

    public init(date: Date, setCount: Int?) {
        self.date = date
        self.setCount = setCount
    }
}

/// One set the user did, just enough to show activity and a short analysis. Its own type (not `Plan`'s
/// `LoggedSet`) so Insights does not need to depend on the Plan module: the caller (`ProgressModel`) maps
/// its stored sets into this, the same way it already turns Health snapshots and check-ins into this
/// module's own types.
public struct LoggedActivity: Sendable {
    public var exerciseId: String
    public var date: Date

    public init(exerciseId: String, date: Date) {
        self.exerciseId = exerciseId
        self.date = date
    }
}

/// A GitHub-style activity calendar and a short analysis of the last two weeks.
public struct ActivityLog: Equatable, Sendable {
    /// Oldest first, starting on a Monday so a grid of `weeks` columns lines up by weekday.
    public var days: [ActivityDay]
    /// Consecutive days up to and including today with at least one set logged.
    public var currentStreakDays: Int
    /// The exercise done on the most days in the last 7 days, catalog id (the view resolves the name).
    public var topExerciseId: String?
    /// One or two sentences about the last week, e.g. "W ostatnim tygodniu: 3 treningi, 24 serie. Więcej
    /// treningów niż tydzień wcześniej."
    public var summary: String

    public var hasAnyActivity: Bool { days.contains { ($0.setCount ?? 0) > 0 } }
}

/// Data for the "Postępy" screen: technique score over time, a simple recovery index and mood over time, and
/// a GitHub-style calendar of training activity with a short analysis. Pure and deterministic. The recovery
/// index is a helper for the chart (engineering values, not a health score).
public struct ProgressReport: Equatable, Sendable {
    public var technique: TechniqueProgress?
    /// Oldest first, only days that have a snapshot.
    public var recovery: [DayValue]
    /// Oldest first, only days that have a check-in. Mood 1...5 scaled to 0...100.
    public var mood: [DayValue]
    /// One sentence about the last days, nil when there is too little data.
    public var trendSentence: String?
    public var activity: ActivityLog

    public var isEmpty: Bool { technique == nil && recovery.isEmpty && mood.isEmpty && !activity.hasAnyActivity }

    public init(technique: TechniqueProgress?, recovery: [DayValue], mood: [DayValue], trendSentence: String?,
                activity: ActivityLog = ActivityLog.make(sets: [])) {
        self.technique = technique
        self.recovery = recovery
        self.mood = mood
        self.trendSentence = trendSentence
        self.activity = activity
    }

    public static let componentNames: [String: String] = [
        "depth": "głębokość", "torso": "tułów", "repeatability": "powtarzalność", "tempo": "tempo",
    ]

    /// - Parameters:
    ///   - results: technique analyses in any order.
    ///   - snapshots / checkIns: any order, any length. Only the last `days` days are used.
    ///   - activitySets: every logged set (not just ones with a weight), any order, any length — the
    ///     calendar covers its own window (`activityWeeks`), independent of `days`.
    public static func make(results: [TechniqueResult], snapshots: [RecoverySnapshot], checkIns: [CheckIn],
                            activitySets: [LoggedActivity] = [],
                            days: Int = 14, activityWeeks: Int = 12, now: Date = Date(), calendar: Calendar = .current,
                            thresholds: InsightThresholds = .default) -> ProgressReport {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today

        let recovery = snapshots.filter { $0.date >= start }
            .map { DayValue(date: calendar.startOfDay(for: $0.date), value: recoveryIndex($0)) }
            .sortedByDate()
        // One value per day: the latest check-in of the day.
        var moodByDay: [Date: CheckIn] = [:]
        for c in checkIns where c.date >= start {
            let day = calendar.startOfDay(for: c.date)
            if let current = moodByDay[day], current.date >= c.date { continue }
            moodByDay[day] = c
        }
        let mood = moodByDay.map { DayValue(date: $0.key, value: moodScale($0.value.mood)) }.sortedByDate()

        let latestSnapshot = snapshots.max { $0.date < $1.date }
        return ProgressReport(
            technique: techniqueProgress(results),
            recovery: recovery, mood: mood,
            trendSentence: trend(recovery: recovery, mood: mood, latest: latestSnapshot, thresholds: thresholds),
            activity: ActivityLog.make(sets: activitySets, weeks: activityWeeks, now: now, calendar: calendar))
    }

    // MARK: Recovery index

    /// 0...100 from sleep (50%), HRV against the personal baseline (30%) and resting heart rate against the
    /// baseline (20%). Sleep counts up to 7.5 h, HRV and heart rate are full marks at or better than baseline.
    public static func recoveryIndex(_ s: RecoverySnapshot) -> Int {
        let sleep = min(1, Double(s.sleepMinutes) / 450)
        let hrv = min(1, max(0, 1 + s.hrvDeltaRatio * 2))
        let rhr = min(1, max(0, 1 - Double(s.restingHeartRate - s.restingHeartRateBaseline) / 10))
        return Int((100 * (0.5 * sleep + 0.3 * hrv + 0.2 * rhr)).rounded())
    }

    /// Mood 1...5 on a 0...100 axis.
    public static func moodScale(_ mood: Int) -> Int { (min(5, max(1, mood)) - 1) * 25 }

    // MARK: Technique

    public static func techniqueProgress(_ results: [TechniqueResult]) -> TechniqueProgress? {
        let sorted = results.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last else { return nil }
        let points = sorted.map { ScorePoint(date: $0.date, score: $0.score) }
        let delta = last.score - first.score

        var sentences: [String] = []
        if sorted.count == 1 {
            sentences.append("To pierwsza analiza. Kolejne pokażą, jak zmienia się wynik.")
        } else if delta >= 3 {
            sentences.append("Wynik rośnie od \(sorted.count) analiz.")
        } else if delta <= -3 {
            sentences.append("Wynik jest niższy niż w pierwszej analizie.")
        } else {
            sentences.append("Wynik jest stabilny od \(sorted.count) analiz.")
        }
        let comps = last.componentScores.filter { componentNames[$0.key] != nil }
        if comps.count >= 2, let best = comps.max(by: { $0.value < $1.value }),
           let worst = comps.min(by: { $0.value < $1.value }) {
            sentences.append("Najmocniejsza strona: \(componentNames[best.key] ?? best.key).")
            if worst.value < 70 { sentences.append("Do poprawy: \(componentNames[worst.key] ?? worst.key).") }
        }
        return TechniqueProgress(points: points, latest: last.score, deltaFromStart: delta,
                                 summary: sentences.joined(separator: " "))
    }

    // MARK: Trend sentence

    private static func trend(recovery: [DayValue], mood: [DayValue], latest: RecoverySnapshot?,
                              thresholds: InsightThresholds) -> String? {
        let recoveryChange = lastTwoVersusEarlier(recovery)
        let moodChange = lastTwoVersusEarlier(mood)
        guard recoveryChange != nil || moodChange != nil else { return nil }

        let recoveryDropped = (recoveryChange ?? 0) <= -10
        let moodDropped = (moodChange ?? 0) <= -10
        let improved = (recoveryChange ?? 0) >= 10 || (moodChange ?? 0) >= 10

        if recoveryDropped || moodDropped {
            let subject = recoveryDropped && moodDropped ? "regeneracja i nastrój spadły"
                : recoveryDropped ? "regeneracja spadła" : "nastrój spadł"
            var sentence = "W ostatnich dwóch dniach \(subject)"
            if recoveryDropped, let latest {
                var reasons: [String] = []
                if latest.sleepMinutes < thresholds.signals.sleepMinutesLow { reasons.append("krótszy sen") }
                if latest.hrvDeltaRatio < thresholds.signals.hrvBelowBaselineRatio { reasons.append("niższe HRV") }
                if latest.restingHeartRate - latest.restingHeartRateBaseline > thresholds.signals.restingHeartRateAboveBaseline {
                    reasons.append("wyższe tętno spoczynkowe")
                }
                if !reasons.isEmpty { sentence += ": " + reasons.joined(separator: " i ") }
            }
            return sentence + "."
        }
        if improved { return "W ostatnich dwóch dniach regeneracja i nastrój wyglądają lepiej niż wcześniej." }
        return "Regeneracja i nastrój są stabilne."
    }

    /// Mean of the last two points minus the mean of all earlier ones. Needs at least four points in total.
    private static func lastTwoVersusEarlier(_ series: [DayValue]) -> Double? {
        guard series.count >= 4 else { return nil }
        let recent = series.suffix(2).map { Double($0.value) }
        let earlier = series.dropLast(2).map { Double($0.value) }
        return recent.reduce(0, +) / Double(recent.count) - earlier.reduce(0, +) / Double(earlier.count)
    }
}

private extension Array where Element == DayValue {
    func sortedByDate() -> [DayValue] { sorted { $0.date < $1.date } }
}

extension ActivityLog {
    /// `weeks` full calendar weeks (Monday to Sunday) ending on the week that contains `now`, so the grid is
    /// always a full rectangle: days after today carry `setCount == nil` instead of being left out.
    public static func make(sets: [LoggedActivity], weeks: Int = 12, now: Date = Date(),
                            calendar: Calendar = .current) -> ActivityLog {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday ... 7 = Saturday
        let daysSinceMonday = (weekday + 5) % 7 // Monday -> 0, ..., Sunday -> 6
        let mondayThisWeek = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        let start = calendar.date(byAdding: .day, value: -(max(weeks, 1) - 1) * 7, to: mondayThisWeek) ?? mondayThisWeek

        var countByDay: [Date: Int] = [:]
        for s in sets {
            let day = calendar.startOfDay(for: s.date)
            guard day >= start else { continue }
            countByDay[day, default: 0] += 1
        }

        var days: [ActivityDay] = []
        var cursor = start
        for _ in 0..<(max(weeks, 1) * 7) {
            days.append(ActivityDay(date: cursor, setCount: cursor <= today ? (countByDay[cursor] ?? 0) : nil))
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }

        var streak = 0
        var day = today
        while (countByDay[day] ?? 0) > 0 {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }

        let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        return ActivityLog(days: days, currentStreakDays: streak,
                           topExerciseId: topExerciseId(sets, since: weekAgo),
                           summary: summary(sets, today: today, calendar: calendar))
    }

    private static func topExerciseId(_ sets: [LoggedActivity], since start: Date) -> String? {
        let recent = sets.filter { $0.date >= start }
        guard !recent.isEmpty else { return nil }
        let counts = Dictionary(grouping: recent, by: \.exerciseId).mapValues(\.count)
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.first?.key
    }

    /// "trening"/"treningi"/"treningów", "seria"/"serie"/"serii" — standard Polish plural rule.
    private static func wordForm(_ count: Int, one: String, few: String, many: String) -> String {
        let mod10 = count % 10, mod100 = count % 100
        if count == 1 { return one }
        if (2...4).contains(mod10), !(12...14).contains(mod100) { return few }
        return many
    }

    private static func summary(_ sets: [LoggedActivity], today: Date, calendar: Calendar) -> String {
        func window(daysAgo: Range<Int>) -> (sessions: Int, sets: Int) {
            guard let from = calendar.date(byAdding: .day, value: -(daysAgo.upperBound - 1), to: today),
                let to = calendar.date(byAdding: .day, value: 1 - daysAgo.lowerBound, to: today)
            else { return (0, 0) }
            let start = calendar.startOfDay(for: from)
            let end = calendar.startOfDay(for: to)
            let inRange = sets.filter { $0.date >= start && $0.date < end }
            let days = Set(inRange.map { calendar.startOfDay(for: $0.date) })
            return (days.count, inRange.count)
        }
        let recent = window(daysAgo: 0..<7)
        let earlier = window(daysAgo: 7..<14)
        let training = { (n: Int) in wordForm(n, one: "trening", few: "treningi", many: "treningów") }
        let series = { (n: Int) in wordForm(n, one: "seria", few: "serie", many: "serii") }

        guard recent.sessions > 0 else {
            guard earlier.sessions > 0 else { return "Brak treningów w ostatnich 14 dniach." }
            return "W tym tygodniu bez treningu. W poprzednim: \(earlier.sessions) \(training(earlier.sessions))."
        }
        var sentence = "W ostatnim tygodniu: \(recent.sessions) \(training(recent.sessions)), "
            + "\(recent.sets) \(series(recent.sets))."
        if earlier.sessions > 0 {
            if recent.sessions > earlier.sessions { sentence += " Więcej treningów niż tydzień wcześniej." }
            else if recent.sessions < earlier.sessions { sentence += " Mniej treningów niż tydzień wcześniej." }
        }
        return sentence
    }
}
