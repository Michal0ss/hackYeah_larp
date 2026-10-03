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

    private var activityTypes: [HKQuantityType] {
        [HKQuantityType(.stepCount), HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceWalkingRunning),
         HKQuantityType(.appleExerciseTime), HKQuantityType(.flightsClimbed)]
    }

    /// Asks for the recovery types and the activity types in one sheet. Asking again later only shows the types that
    /// were never asked about, so an existing install picks up the activity types the first time the panel opens.
    public func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        do {
            let types: Set<HKObjectType> = Set([sleepType, restingType, hrvType] as [HKObjectType]).union(activityTypes)
            try await store.requestAuthorization(toShare: [], read: types)
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
        let inBedCount = sleepSamples.count - sleep.count

        let bpm = HKUnit.count().unitDivided(by: .minute())
        let resting = try await HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: restingType, predicate: window)], sortDescriptors: [],
            limit: HKObjectQueryNoLimit).result(for: store)
            .map { DatedValue(date: $0.endDate, value: $0.quantity.doubleValue(for: bpm)) }

        let hrv = try await HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: hrvType, predicate: window)], sortDescriptors: [],
            limit: HKObjectQueryNoLimit).result(for: store)
            .map { DatedValue(date: $0.endDate, value: $0.quantity.doubleValue(for: .secondUnit(with: .milli))) }

        return HealthSamples(sleep: sleep, restingHeartRate: resting, hrv: hrv, inBedCount: inBedCount)
    }

    public func dailyActivity(from start: Date, to end: Date) async throws -> [DailyActivity] {
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: start)
        let window = HKQuery.predicateForSamples(withStart: anchor, end: end, options: [])

        /// Per-day sums. HealthKit merges phone and watch itself, so steps are not counted twice.
        func dailySums(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> [Date: Double] {
            let query = HKStatisticsCollectionQueryDescriptor(
                predicate: .quantitySample(type: HKQuantityType(identifier), predicate: window),
                options: .cumulativeSum, anchorDate: anchor, intervalComponents: DateComponents(day: 1))
            let collection = try await query.result(for: store)
            var sums: [Date: Double] = [:]
            collection.enumerateStatistics(from: anchor, to: end) { statistics, _ in
                if let sum = statistics.sumQuantity() {
                    sums[calendar.startOfDay(for: statistics.startDate)] = sum.doubleValue(for: unit)
                }
            }
            return sums
        }

        let steps = try await dailySums(.stepCount, unit: .count())
        let energy = try await dailySums(.activeEnergyBurned, unit: .kilocalorie())
        let meters = try await dailySums(.distanceWalkingRunning, unit: .meter())
        let exercise = try await dailySums(.appleExerciseTime, unit: .minute())
        let flights = try await dailySums(.flightsClimbed, unit: .count())

        let days = Set(steps.keys).union(energy.keys).union(meters.keys).union(exercise.keys).union(flights.keys)
        return days.sorted().map { day in
            DailyActivity(date: day, steps: steps[day].map { Int($0.rounded()) },
                          activeEnergyKcal: energy[day].map { Int($0.rounded()) },
                          distanceKm: meters[day].map { $0 / 1000 },
                          exerciseMinutes: exercise[day].map { Int($0.rounded()) },
                          flightsClimbed: flights[day].map { Int($0.rounded()) })
        }
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
