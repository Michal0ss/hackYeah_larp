#if DEBUG
import Foundation
import HealthKit

/// Debug builds only. The simulator's Health is empty, so this writes a fortnight of believable sleep, resting heart
/// rate and HRV into it. That lets the whole real read path (permission, queries, aggregation, strip) be checked
/// without a phone and a watch.
///
///     xcrun simctl launch <device> <bundle id> -seed-health          write the data (asks for Health permission once)
///     xcrun simctl launch <device> <bundle id> -seed-health-clear    remove what this wrote
///
/// Everything written carries `FormaDebugSeed` metadata, so only our own samples are ever removed.
enum HealthDebugSeeder {
    private static let marker = "FormaDebugSeed"
    private static var ran = false

    static func runIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        guard !ran, HKHealthStore.isHealthDataAvailable() else { return }
        if arguments.contains("-seed-health-clear") {
            ran = true
            await clear()
        } else if arguments.contains("-seed-health") {
            ran = true
            await seed()
        }
    }

    private static var types: Set<HKSampleType> {
        [HKCategoryType(.sleepAnalysis), HKQuantityType(.restingHeartRate), HKQuantityType(.heartRateVariabilitySDNN)]
    }

    private static func clear() async {
        let store = HKHealthStore()
        guard (try? await store.requestAuthorization(toShare: types, read: types)) != nil else { return }
        await deleteSeeded(in: store)
    }

    private static func deleteSeeded(in store: HKHealthStore) async {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: marker)
        for type in types { _ = try? await store.deleteObjects(of: type, predicate: predicate) }
    }

    private static func seed() async {
        let store = HKHealthStore()
        guard (try? await store.requestAuthorization(toShare: types, read: types)) != nil else { return }
        await deleteSeeded(in: store)

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        // Today is a short night with a lower HRV and a higher resting heart rate than the days before.
        let sleepMinutes = [385, 430, 455, 440, 410, 470, 445, 420, 450, 460, 435, 445, 465, 450, 440]
        let restingRates = [58, 55, 54, 56, 55, 54, 55, 56, 55, 54, 55, 56, 54, 55, 55]
        let hrvMeans = [41, 49, 52, 47, 48, 51, 49, 47, 50, 48, 49, 47, 52, 48, 49]
        let metadata: [String: Any] = [marker: true]
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        let milliseconds = HKUnit.secondUnit(with: .milli)

        func at(_ day: Date, _ hour: Int, _ minute: Int = 0) -> Date {
            min(calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day, now.addingTimeInterval(-60))
        }

        var samples: [HKSample] = []
        for offset in 0..<sleepMinutes.count {
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let wake = at(day, 6, 40 + (offset % 3) * 10)
            // One night as four stages that end at the wake-up time.
            let total = Double(sleepMinutes[offset]) * 60
            let stages: [(HKCategoryValueSleepAnalysis, Double)] = [(.asleepCore, 0.35), (.asleepDeep, 0.2), (.asleepCore, 0.2), (.asleepREM, 0.25)]
            var cursor = wake.addingTimeInterval(-total)
            for (stage, share) in stages {
                let end = cursor.addingTimeInterval(total * share)
                samples.append(HKCategorySample(type: HKCategoryType(.sleepAnalysis), value: stage.rawValue,
                                                start: cursor, end: end, metadata: metadata))
                cursor = end
            }
            let resting = at(day, 7, 30)
            samples.append(HKQuantitySample(type: HKQuantityType(.restingHeartRate),
                                            quantity: HKQuantity(unit: perMinute, doubleValue: Double(restingRates[offset])),
                                            start: resting, end: resting, metadata: metadata))
            for (hour, minute, delta) in [(3, 10, -3.0), (4, 20, 0.0), (5, 30, 3.0)] {
                let moment = at(day, hour, minute)
                samples.append(HKQuantitySample(type: HKQuantityType(.heartRateVariabilitySDNN),
                                                quantity: HKQuantity(unit: milliseconds, doubleValue: Double(hrvMeans[offset]) + delta),
                                                start: moment, end: moment, metadata: metadata))
            }
        }
        try? await store.save(samples)
    }
}
#endif
