import Foundation

/// One day of general activity from Apple Health (steps, energy, distance...). Every number can be missing: a phone
/// without a watch has steps but no exercise minutes, a new phone has nothing at all.
public struct DailyActivity: Equatable, Sendable, Identifiable {
    /// Start of the day.
    public var date: Date
    public var steps: Int?
    /// Active energy (what moving burned, without the resting part), in kilocalories.
    public var activeEnergyKcal: Int?
    public var distanceKm: Double?
    /// Apple's "exercise minutes" (brisk movement), measured by the watch or the phone.
    public var exerciseMinutes: Int?
    public var flightsClimbed: Int?

    public var id: Date { date }

    public init(date: Date, steps: Int? = nil, activeEnergyKcal: Int? = nil, distanceKm: Double? = nil,
                exerciseMinutes: Int? = nil, flightsClimbed: Int? = nil) {
        self.date = date
        self.steps = steps
        self.activeEnergyKcal = activeEnergyKcal
        self.distanceKm = distanceKm
        self.exerciseMinutes = exerciseMinutes
        self.flightsClimbed = flightsClimbed
    }

    public var isEmpty: Bool { ActivityMetric.allCases.allSatisfy { value(for: $0) == nil } }

    public func value(for metric: ActivityMetric) -> Double? {
        switch metric {
        case .steps: return steps.map(Double.init)
        case .activeEnergy: return activeEnergyKcal.map(Double.init)
        case .distance: return distanceKm
        case .exercise: return exerciseMinutes.map(Double.init)
        case .flights: return flightsClimbed.map(Double.init)
        }
    }
}

/// The numbers the "Dane zdrowotne" panel shows and charts, with their Polish names, units and formatting.
public enum ActivityMetric: String, CaseIterable, Sendable, Identifiable {
    case steps, activeEnergy, distance, exercise, flights

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .steps: return "Kroki"
        case .activeEnergy: return "Kalorie aktywne"
        case .distance: return "Dystans"
        case .exercise: return "Ćwiczenia"
        case .flights: return "Piętra"
        }
    }

    /// Short enough for a segmented control.
    public var shortTitle: String {
        switch self {
        case .activeEnergy: return "Kalorie"
        default: return title
        }
    }

    public var unit: String? {
        switch self {
        case .steps, .flights: return nil
        case .activeEnergy: return "kcal"
        case .distance: return "km"
        case .exercise: return "min"
        }
    }

    public var systemImage: String {
        switch self {
        case .steps: return "figure.walk"
        case .activeEnergy: return "flame.fill"
        case .distance: return "location.fill"
        case .exercise: return "timer"
        case .flights: return "figure.stairs"
        }
    }

    /// The number only, Polish style: "8 432" (non-breaking space), "5,3" (decimal comma).
    public func formatted(_ value: Double) -> String {
        switch self {
        case .distance:
            return String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
        default:
            return Self.grouped(Int(value.rounded()))
        }
    }

    /// The number with its unit, e.g. "412 kcal"; steps and flights have none.
    public func formattedWithUnit(_ value: Double) -> String {
        [formatted(value), unit].compactMap { $0 }.joined(separator: " ")
    }

    static func grouped(_ value: Int) -> String {
        let digits = String(abs(value))
        var result = ""
        for (index, character) in digits.reversed().enumerated() {
            if index > 0, index % 3 == 0 { result.append("\u{00A0}") }
            result.append(character)
        }
        return (value < 0 ? "-" : "") + String(result.reversed())
    }
}

/// What the "Dane zdrowotne" panel shows: the last days of activity plus the recovery numbers (sleep, resting heart
/// rate, HRV).
public struct HealthOverview: Equatable, Sendable {
    /// One entry per day, newest first; the first one is today. A day without data is an empty `DailyActivity`.
    public var activity: [DailyActivity]
    /// Sleep, resting heart rate and HRV per day, newest first (only days that have at least one number).
    public var recovery: [HealthDaySummary]
    /// True for sample data. The UI must show the "Dane przykładowe" badge.
    public var isSimulated: Bool

    public init(activity: [DailyActivity] = [], recovery: [HealthDaySummary] = [], isSimulated: Bool = false) {
        self.activity = activity
        self.recovery = recovery
        self.isSimulated = isSimulated
    }

    public var hasData: Bool { activity.contains { !$0.isEmpty } || recovery.contains { !$0.isEmpty } }

    /// Today's activity (nil when the overview is empty).
    public var today: DailyActivity? { activity.first }

    /// The mean over the days that have the number. Days without data do not count as zero.
    public func average(of metric: ActivityMetric) -> Double? {
        let values = activity.compactMap { $0.value(for: metric) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Believable sample numbers for the last `days` days ("Dane przykładowe"), recovery taken from `recovery`.
    public static func sample(days: Int, now: Date, calendar: Calendar, recovery: [HealthDaySummary]) -> HealthOverview {
        let steps = [6_840, 9_120, 11_350, 7_420, 8_030, 10_210, 5_640, 8_760]
        let energy = [310, 420, 520, 340, 380, 470, 260, 400]
        let distance = [4.9, 6.6, 8.2, 5.3, 5.8, 7.4, 4.0, 6.3]
        let exercise = [22, 38, 55, 26, 30, 47, 15, 36]
        let flights = [8, 12, 15, 9, 10, 14, 6, 11]
        let today = calendar.startOfDay(for: now)
        let activity = (0..<max(days, 0)).compactMap { offset -> DailyActivity? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let i = offset % steps.count
            return DailyActivity(date: day, steps: steps[i], activeEnergyKcal: energy[i], distanceKm: distance[i],
                                 exerciseMinutes: exercise[i], flightsClimbed: flights[i])
        }
        return HealthOverview(activity: activity, recovery: recovery, isSimulated: true)
    }
}

/// The panel's data source: `HealthKitService` on a phone, a fake in tests.
public protocol HealthOverviewProviding: Sendable {
    func overview(days: Int) async -> HealthOverview
}
