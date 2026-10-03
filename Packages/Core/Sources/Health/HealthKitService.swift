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

/// `RecoveryProviding`, `HealthSummaryProviding` and `HealthAuthorizing` on top of Apple Health.
///
/// Returns only daily summaries with a personal baseline, never raw samples. When Apple Health has no data at all
/// (no access, empty, error, or the gate says "sample data") it falls back to the "Anna" sample data, marked
/// `isSimulated` so the UI shows the "Dane przykładowe" badge. As soon as Health has *any* real number, only real
/// data is returned: sample and real data are never mixed, even when the real data is incomplete (then `snapshots`
/// has no complete day and the rule engine simply has no recovery signal).
public struct HealthKitService: RecoveryProviding, HealthSummaryProviding, HealthAuthorizing {
    private let source: HealthSampleSource
    private let aggregator: RecoveryAggregator
    private let useSampleFallback: Bool
    private let gate: HealthDataGate
    private let now: @Sendable () -> Date

    public init(source: HealthSampleSource = HKHealthSampleSource(), aggregator: RecoveryAggregator = RecoveryAggregator(),
                useSampleFallback: Bool = true, gate: HealthDataGate = .shared,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source
        self.aggregator = aggregator
        self.useSampleFallback = useSampleFallback
        self.gate = gate
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
        if let real = await realSummaries(days: days), !real.isEmpty { return real.compactMap(\.snapshot) }
        return useSampleFallback ? Array(SampleData.recovery.prefix(days)) : []
    }

    // MARK: HealthSummaryProviding

    public func summaries(days: Int) async -> [HealthDaySummary] {
        guard days > 0 else { return [] }
        if let real = await realSummaries(days: days), !real.isEmpty { return real }
        return useSampleFallback ? SampleData.recovery.prefix(days).map(HealthDaySummary.init) : []
    }

    /// nil when real data must not or cannot be read (gate closed, Health unavailable, read failed).
    private func realSummaries(days: Int) async -> [HealthDaySummary]? {
        guard gate.allowsRealData, source.isAvailable else { return nil }
        let end = now()
        let lookback = aggregator.lookbackDays(for: days)
        guard let start = aggregator.calendar.date(byAdding: .day, value: -lookback,
                                                   to: aggregator.calendar.startOfDay(for: end)) else { return nil }
        guard let samples = try? await source.samples(from: start, to: end) else { return nil }
        return aggregator.summaries(from: samples, days: days, now: end)
    }
}
