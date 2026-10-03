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

public struct WeightPoint: Equatable, Sendable, Identifiable {
    public var id: Date { date }
    public var date: Date
    public var weightKg: Double

    public init(date: Date, weightKg: Double) {
        self.date = date
        self.weightKg = weightKg
    }
}

/// One logged set with a weight, enough to trend it over time. Its own type (not `Plan`'s `LoggedSet`) so
/// Insights does not need to depend on the Plan module: the caller (`ProgressModel`) maps its stored sets
/// into this, the same way it already turns Health snapshots and check-ins into this module's own types.
public struct WeightedSet: Sendable {
    public var exerciseId: String
    public var date: Date
    public var weightKg: Double

    public init(exerciseId: String, date: Date, weightKg: Double) {
        self.exerciseId = exerciseId
        self.date = date
        self.weightKg = weightKg
    }
}

public struct StrengthProgress: Equatable, Sendable {
    /// The exercise with the most days of logged weight, catalog id (the view resolves the display name).
    public var exerciseId: String
    /// Oldest first, one point per day: the heaviest weight logged that day.
    public var points: [WeightPoint]
    public var latest: Double
    /// Latest minus first weight.
    public var deltaFromStart: Double
    /// One short sentence, e.g. "Ciężar rośnie od 5 dni z zapisem."
    public var summary: String
}

/// Data for the "Postępy" screen: technique score over time, a simple recovery index and mood over time, and the
/// weight progress of the exercise logged on the most days. Pure and deterministic. The recovery index is a helper
/// for the chart (engineering values, not a health score).
public struct ProgressReport: Equatable, Sendable {
    public var technique: TechniqueProgress?
    /// Oldest first, only days that have a snapshot.
    public var recovery: [DayValue]
    /// Oldest first, only days that have a check-in. Mood 1...5 scaled to 0...100.
    public var mood: [DayValue]
    /// One sentence about the last days, nil when there is too little data.
    public var trendSentence: String?
    /// Nil until at least one set with a weight has been logged.
    public var strength: StrengthProgress?

    public var isEmpty: Bool { technique == nil && recovery.isEmpty && mood.isEmpty && strength == nil }

    public init(technique: TechniqueProgress?, recovery: [DayValue], mood: [DayValue], trendSentence: String?,
                strength: StrengthProgress? = nil) {
        self.technique = technique
        self.recovery = recovery
        self.mood = mood
        self.trendSentence = trendSentence
        self.strength = strength
    }

    public static let componentNames: [String: String] = [
        "depth": "głębokość", "torso": "tułów", "repeatability": "powtarzalność", "tempo": "tempo",
    ]

    /// - Parameters:
    ///   - results: technique analyses in any order.
    ///   - snapshots / checkIns: any order, any length. Only the last `days` days are used.
    ///   - weightedSets: logged sets that have a weight, any order, any length. Not limited to `days`: strength,
    ///     like technique, is a trend across sessions rather than a daily health signal.
    public static func make(results: [TechniqueResult], snapshots: [RecoverySnapshot], checkIns: [CheckIn],
                            weightedSets: [WeightedSet] = [],
                            days: Int = 14, now: Date = Date(), calendar: Calendar = .current,
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
            strength: strengthProgress(weightedSets, calendar: calendar))
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

    private static func techniqueProgress(_ results: [TechniqueResult]) -> TechniqueProgress? {
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

    // MARK: Strength

    /// The exercise with the most distinct days of logged weight (ties broken by id, so the result is
    /// deterministic) — showing every exercise at once would need a picker, not a glance on "Postępy".
    private static func strengthProgress(_ sets: [WeightedSet], calendar: Calendar) -> StrengthProgress? {
        guard !sets.isEmpty else { return nil }
        let byExercise = Dictionary(grouping: sets, by: \.exerciseId)
        let daysLogged: (String) -> Int = { id in Set((byExercise[id] ?? []).map { calendar.startOfDay(for: $0.date) }).count }
        let ranked = byExercise.keys.map { ($0, daysLogged($0)) }.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
        guard let exerciseId = ranked.first?.0 else { return nil }

        // One point per day: the heaviest weight logged that day (several sets of the same exercise, e.g. a
        // warm-up followed by the working weight, should not look like the weight went up and back down).
        var maxByDay: [Date: Double] = [:]
        for s in byExercise[exerciseId] ?? [] {
            let day = calendar.startOfDay(for: s.date)
            maxByDay[day] = max(maxByDay[day] ?? 0, s.weightKg)
        }
        let points = maxByDay.map { WeightPoint(date: $0.key, weightKg: $0.value) }.sorted { $0.date < $1.date }
        guard let first = points.first, let last = points.last else { return nil }
        let delta = last.weightKg - first.weightKg

        let summary: String
        if points.count == 1 {
            summary = "To pierwszy zapisany ciężar. Kolejne treningi pokażą, jak się zmienia."
        } else if delta >= 1 {
            summary = "Ciężar rośnie od \(points.count) dni z zapisem."
        } else if delta <= -1 {
            summary = "Ostatni ciężar jest niższy niż na początku."
        } else {
            summary = "Ciężar jest stabilny od \(points.count) dni z zapisem."
        }
        return StrengthProgress(exerciseId: exerciseId, points: points, latest: last.weightKg,
                                deltaFromStart: delta, summary: summary)
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
