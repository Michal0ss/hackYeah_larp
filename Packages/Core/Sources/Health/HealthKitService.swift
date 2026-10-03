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

/// `RecoveryProviding` and `HealthAuthorizing` on top of Apple Health.
///
/// Returns only daily summaries with a personal baseline, never raw samples. When Health has no usable data
/// (no access, no watch, empty simulator, error) it falls back to the "Anna" sample data, which is marked
/// `isSimulated` so the UI shows the "Dane przykładowe" badge. The fallback can be switched off.
public struct HealthKitService: RecoveryProviding, HealthAuthorizing {
    private let source: HealthSampleSource
    private let aggregator: RecoveryAggregator
    private let useSampleFallback: Bool
    private let now: @Sendable () -> Date

    public init(source: HealthSampleSource = HKHealthSampleSource(), aggregator: RecoveryAggregator = RecoveryAggregator(),
                useSampleFallback: Bool = true, now: @escaping @Sendable () -> Date = { Date() }) {
        self.source = source
        self.aggregator = aggregator
        self.useSampleFallback = useSampleFallback
        self.now = now
    }

    // MARK: HealthAuthorizing

    /// HealthKit never says whether *read* access was granted (privacy by design), so true means the request
    /// went through. Whether data actually flows shows up in `snapshots(days:)`.
    public func requestAccess() async -> Bool {
        guard source.isAvailable else { return false }
        return await source.requestAccess()
    }

    // MARK: RecoveryProviding

    public func snapshots(days: Int) async -> [RecoverySnapshot] {
        guard days > 0 else { return [] }
        if source.isAvailable, let real = await realSnapshots(days: days), !real.isEmpty { return real }
        return useSampleFallback ? Array(SampleData.recovery.prefix(days)) : []
    }

    private func realSnapshots(days: Int) async -> [RecoverySnapshot]? {
        let end = now()
        let lookback = aggregator.lookbackDays(for: days)
        guard let start = aggregator.calendar.date(byAdding: .day, value: -lookback,
                                                   to: aggregator.calendar.startOfDay(for: end)) else { return nil }
        guard let samples = try? await source.samples(from: start, to: end) else { return nil }
        return aggregator.snapshots(from: samples, days: days, now: end)
    }
}
