import Foundation
import Contracts

public struct SeriesPoint: Equatable, Sendable, Identifiable {
    public var id: Date { date }
    public var date: Date
    public var value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// The chart on "Postępy" for technique: the person picks the exercise and what to follow (the overall score or
/// one of its parts). Pure and deterministic, so the choices can be tested without a screen.
public enum TechniqueSeries {
    /// Parts of the score, in the order they are offered. Only those present in the results are shown.
    public static let componentOrder = ["depth", "torso", "repeatability", "tempo"]

    /// Exercises that have an analysis, the most analysed first (ties by id).
    public static func exerciseIds(in results: [TechniqueResult]) -> [String] {
        let counts = Dictionary(grouping: results, by: \.exerciseId).mapValues(\.count)
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    /// Score parts that at least one analysis of the exercise has, in `componentOrder`.
    public static func components(in results: [TechniqueResult], exerciseId: String) -> [String] {
        let present = Set(results.filter { $0.exerciseId == exerciseId }.flatMap { $0.componentScores.keys })
        return componentOrder.filter(present.contains)
    }

    /// Oldest first, one point per analysis. `component == nil` is the overall score. An analysis that lacks the
    /// asked part is left out rather than drawn as zero.
    public static func points(_ results: [TechniqueResult], exerciseId: String, component: String? = nil) -> [SeriesPoint] {
        results.filter { $0.exerciseId == exerciseId }
            .sorted { $0.date < $1.date }
            .compactMap { result in
                let value: Int? = component == nil ? result.score : result.componentScores[component ?? ""]
                return value.map { SeriesPoint(date: result.date, value: Double($0)) }
            }
    }
}

/// One set the user did with its numbers. Its own type (not `Plan`'s `LoggedSet`) so Insights does not depend on Plan.
public struct LoggedLoad: Sendable {
    public var exerciseId: String
    public var date: Date
    /// Nil when no weight was entered (body weight, or the user did not say).
    public var weightKg: Double?
    /// Nil for exercises counted in seconds.
    public var reps: Int?

    public init(exerciseId: String, date: Date, weightKg: Double? = nil, reps: Int? = nil) {
        self.exerciseId = exerciseId
        self.date = date
        self.weightKg = weightKg
        self.reps = reps
    }
}

public enum LoadMetric: String, CaseIterable, Sendable {
    case weight, reps

    func value(of set: LoggedLoad) -> Double? {
        switch self {
        case .weight: return set.weightKg
        case .reps: return set.reps.map(Double.init)
        }
    }
}

/// The chart on "Postępy" for training load: weight or repetitions over time, for one exercise at a time.
public enum LoadSeries {
    /// The exercises to offer: first those of the plan, in plan order, then any other exercise that has logged sets
    /// (done earlier, before the plan changed), the most logged days first. An exercise of the plan with nothing logged
    /// yet is still offered, so its chart can say what is missing instead of the exercise being absent.
    public static func exerciseIds(in sets: [LoggedLoad], planned: [String], calendar: Calendar = .current) -> [String] {
        var seen = Set<String>()
        let fromPlan = planned.filter { seen.insert($0).inserted }
        var days: [String: Set<Date>] = [:]
        for set in sets where !seen.contains(set.exerciseId) {
            days[set.exerciseId, default: []].insert(calendar.startOfDay(for: set.date))
        }
        let others = days.sorted { $0.value.count != $1.value.count ? $0.value.count > $1.value.count : $0.key < $1.key }
        return fromPlan + others.map(\.key)
    }

    /// Oldest first, one point per day: the best set of that day (a warm-up before the working weight must not look
    /// like the weight went down).
    public static func points(_ sets: [LoggedLoad], exerciseId: String, metric: LoadMetric,
                              calendar: Calendar = .current) -> [SeriesPoint] {
        var best: [Date: Double] = [:]
        for set in sets where set.exerciseId == exerciseId {
            guard let value = metric.value(of: set) else { continue }
            let day = calendar.startOfDay(for: set.date)
            best[day] = max(best[day] ?? 0, value)
        }
        return best.map { SeriesPoint(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
    }
}
