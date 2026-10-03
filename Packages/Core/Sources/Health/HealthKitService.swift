import Foundation
import Contracts

/// Where raw Health samples come from. The real one is `HKHealthSampleSource`; tests use a fake.
public protocol HealthSampleSource: Sendable {
    /// False on devices without Health data (iPad, simulator without data access, Mac).
    var isAvailable: Bool { get }
    /// Asks for read access to sleep, resting heart rate and HRV. True when the request completed.
    func requestAccess() async -> Bool
    /// Samples between the two dates. Throws when HealthKit refuses or fails.
    func samples(from start: Date, to end: Date) async throws -> HealthSamples
    /// Per-day activity totals (steps, energy, distance, exercise minutes, flights) between the two dates. Days
    /// without data may be left out. Throws when HealthKit refuses or fails.
    func dailyActivity(from start: Date, to end: Date) async throws -> [DailyActivity]
}

public extension HealthSampleSource {
    /// Sources that know nothing about activity (tests, platforms without HealthKit) report no days.
    func dailyActivity(from start: Date, to end: Date) async throws -> [DailyActivity] { [] }
}

/// Lets the app say "use the sample data" even when Apple Health could be read (the user chose sample data in
/// onboarding). Default: real data allowed.
public final class HealthDataGate: @unchecked Sendable {
    public static let shared = HealthDataGate()

    private let lock = NSLock()
    private var allowed = true

    public init() {}

    public var allowsRealData: Bool {
        get { lock.lock(); defer { lock.unlock() }; return allowed }
        set { lock.lock(); allowed = newValue; lock.unlock() }
    }
}

/// Per-day numbers for display (sleep, resting heart rate, HRV), newest first.
public protocol HealthSummaryProviding: Sendable {
    func summaries(days: Int) async -> [HealthDaySummary]
}

/// `RecoveryProviding`, `HealthSummaryProviding`, `HealthOverviewProviding` and `HealthAuthorizing` on top of Apple Health.
///
/// Returns only daily summaries with a personal baseline, never raw samples.
///
/// While Apple Health is readable (available, and the gate says real data is allowed) the answer is always the
/// real one, even when it is empty or incomplete: "Health has nothing for you yet" is shown as "no data", never
/// as made-up numbers. Only when real data does not apply (Health unavailable, or the user chose sample data in
/// onboarding and the gate is closed) it falls back to the "Anna" sample data, marked `isSimulated` so the UI
/// shows the "Dane przykładowe" badge. Sample and real data are never mixed. Incomplete real data gives
/// `snapshots` no complete day, so the rule engine simply has no recovery signal.
public struct HealthKitService: RecoveryProviding, HealthSummaryProviding, HealthOverviewProviding, HealthAuthorizing {
    private let source: HealthSampleSource
    private let aggregator: RecoveryAggregator
    private let useSampleFallback: Bool
    private let gate: HealthDataGate
    private let readLog: HealthReadLog
    private let now: @Sendable () -> Date

    public init(source: HealthSampleSource = HKHealthSampleSource(), aggregator: RecoveryAggregator = RecoveryAggregator(),
                useSampleFallback: Bool = true, gate: HealthDataGate = .shared,
                readLog: HealthReadLog = .shared,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source
        self.aggregator = aggregator
        self.useSampleFallback = useSampleFallback
        self.gate = gate
        self.readLog = readLog
        self.now = now
    }

    // MARK: HealthAuthorizing

    /// HealthKit never says whether *read* access was granted (privacy by design), so true means the request
    /// went through. Whether data actually flows shows up in `summaries(days:)` and `snapshots(days:)`.
    public func requestAccess() async -> Bool {
        guard source.isAvailable else { return false }
        return await source.requestAccess()
    }

    // MARK: RecoveryProviding

    public func snapshots(days: Int) async -> [RecoverySnapshot] {
        guard days > 0 else { return [] }
        if let real = await realSummaries(days: days) { return real.compactMap(\.snapshot) }
        return useSampleFallback ? Array(SampleData.recovery.prefix(days)) : []
    }

    // MARK: HealthSummaryProviding

    public func summaries(days: Int) async -> [HealthDaySummary] {
        guard days > 0 else { return [] }
        if let real = await realSummaries(days: days) { return real }
        return useSampleFallback ? SampleData.recovery.prefix(days).map(HealthDaySummary.init) : []
    }

    // MARK: HealthOverviewProviding

    /// The panel's data: activity and recovery for the last `days` days. Real while Apple Health is readable (a day or
    /// the whole answer may be empty, which means "no data"), sample data (`isSimulated`) only when real data does not
    /// apply, same rule as `summaries(days:)`.
    public func overview(days: Int) async -> HealthOverview {
        guard days > 0 else { return HealthOverview() }
        let recovery = await summaries(days: days)
        let calendar = aggregator.calendar
        let end = now()
        guard realDataApplies else {
            guard useSampleFallback else { return HealthOverview(recovery: recovery) }
            return .sample(days: days, now: end, calendar: calendar, recovery: recovery)
        }
        let today = calendar.startOfDay(for: end)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
            return HealthOverview(recovery: recovery)
        }
        let read = (try? await source.dailyActivity(from: start, to: end)) ?? []
        var byDay: [Date: DailyActivity] = [:]
        for day in read { byDay[calendar.startOfDay(for: day.date)] = day }
        // Exactly `days` entries, newest first, so the first one is today and a quiet day is an empty entry.
        let activity = (0..<days).compactMap { offset -> DailyActivity? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            var entry = byDay[day] ?? DailyActivity(date: day)
            entry.date = day
            return entry
        }
        return HealthOverview(activity: activity, recovery: recovery)
    }

    /// Real data applies while the gate allows it and Health exists on this device.
    private var realDataApplies: Bool { gate.allowsRealData && source.isAvailable }

    /// nil when real data does not apply (gate closed, Health unavailable). Otherwise the real days, which is an
    /// empty list when Health has nothing or the read failed (e.g. the phone is locked): that means "no data".
    private func realSummaries(days: Int) async -> [HealthDaySummary]? {
        guard realDataApplies else { return nil }
        let end = now()
        let lookback = aggregator.lookbackDays(for: days)
        guard let start = aggregator.calendar.date(byAdding: .day, value: -lookback,
                                                   to: aggregator.calendar.startOfDay(for: end)) else { return [] }
        let samples: HealthSamples
        do {
            samples = try await source.samples(from: start, to: end)
        } catch {
            readLog.last = HealthReadReport(lookbackDays: lookback, errorDescription: error.localizedDescription)
            return []
        }
        readLog.last = HealthReadReport(samples: samples, lookbackDays: lookback)
        return aggregator.summaries(from: samples, days: days, now: end)
    }
}
