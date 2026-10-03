import Foundation

#if canImport(HealthKit)
import HealthKit

/// Reads sleep, resting heart rate and HRV from Apple Health (read only, nothing is written or sent).
public struct HKHealthSampleSource: HealthSampleSource, @unchecked Sendable {
    private let store = HKHealthStore()

    public init() {}

    private var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }
    private var restingType: HKQuantityType { HKQuantityType(.restingHeartRate) }
    private var hrvType: HKQuantityType { HKQuantityType(.heartRateVariabilitySDNN) }

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    public func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [sleepType, restingType, hrvType])
            return true
        } catch {
            return false
        }
    }

    public func samples(from start: Date, to end: Date) async throws -> HealthSamples {
        let window = HKQuery.predicateForSamples(withStart: start, end: end, options: [])

        let sleepSamples = try await HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: window)], sortDescriptors: [],
            limit: HKObjectQueryNoLimit).result(for: store)
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let sleep = sleepSamples.filter { asleep.contains($0.value) }
            .map { SleepInterval(start: $0.startDate, end: $0.endDate) }

        let bpm = HKUnit.count().unitDivided(by: .minute())
        let resting = try await HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: restingType, predicate: window)], sortDescriptors: [],
            limit: HKObjectQueryNoLimit).result(for: store)
            .map { DatedValue(date: $0.endDate, value: $0.quantity.doubleValue(for: bpm)) }

        let hrv = try await HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: hrvType, predicate: window)], sortDescriptors: [],
            limit: HKObjectQueryNoLimit).result(for: store)
            .map { DatedValue(date: $0.endDate, value: $0.quantity.doubleValue(for: .secondUnit(with: .milli))) }

        return HealthSamples(sleep: sleep, restingHeartRate: resting, hrv: hrv)
    }
}
#else
/// Placeholder on platforms without HealthKit: reports "not available", so the service uses the sample fallback.
public struct HKHealthSampleSource: HealthSampleSource {
    public init() {}
    public var isAvailable: Bool { false }
    public func requestAccess() async -> Bool { false }
    public func samples(from start: Date, to end: Date) async throws -> HealthSamples { HealthSamples() }
}
#endif
