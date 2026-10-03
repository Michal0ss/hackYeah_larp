import Foundation
import Contracts

/// A period of sleep (any "asleep" stage). In-bed and awake periods are filtered out by the sample source.
public struct SleepInterval: Equatable, Sendable {
    public var start: Date
    public var end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

public struct DatedValue: Equatable, Sendable {
    public var date: Date
    public var value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// Raw samples as read from Apple Health. They never leave this module: only `RecoverySnapshot` summaries do.
public struct HealthSamples: Equatable, Sendable {
    public var sleep: [SleepInterval]
    /// Resting heart rate in beats per minute.
    public var restingHeartRate: [DatedValue]
    /// HRV (SDNN) in milliseconds.
    public var hrv: [DatedValue]

    public init(sleep: [SleepInterval] = [], restingHeartRate: [DatedValue] = [], hrv: [DatedValue] = []) {
        self.sleep = sleep
        self.restingHeartRate = restingHeartRate
        self.hrv = hrv
    }
}

/// Turns raw Health samples into daily `RecoverySnapshot` summaries with a personal baseline.
/// Pure and deterministic, so it is tested on plain arrays (no HealthKit needed).
///
/// Rules:
/// - Sleep: overlapping intervals (several sources, several stages) are merged so nothing is counted twice,
///   and each interval counts for the day it ended on (the night belongs to the morning you woke up).
///   Daytime naps are summed in as well.
/// - Resting heart rate: the latest value of the day. HRV: the mean of the day's samples.
/// - Baseline: the median of the previous `baselineDays` days that have data, never including the day itself.
///   With fewer than `minBaselineDays` earlier days the baseline equals the day's own value, so a new user
///   gets no false signal.
/// - A day becomes a snapshot only when sleep, resting heart rate and HRV are all present.
public struct RecoveryAggregator: Sendable {
    public var calendar: Calendar
    public var baselineDays: Int
    public var minBaselineDays: Int

    public init(calendar: Calendar = .current, baselineDays: Int = 14, minBaselineDays: Int = 3) {
        self.calendar = calendar
        self.baselineDays = baselineDays
        self.minBaselineDays = minBaselineDays
    }

    /// How far back samples must be read to compute `days` snapshots with baselines.
    public func lookbackDays(for days: Int) -> Int { days + baselineDays }

    /// Snapshots for the last `days` days (including today), newest first. Days without full data are skipped.
    public func snapshots(from samples: HealthSamples, days: Int, now: Date = Date(),
                          isSimulated: Bool = false) -> [RecoverySnapshot] {
        guard days > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        let sleepByDay = sleepMinutesPerDay(samples.sleep)
        let rhrByDay = latestPerDay(samples.restingHeartRate)
        let hrvByDay = meanPerDay(samples.hrv)

        var result: [RecoverySnapshot] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let sleep = sleepByDay[day], let rhr = rhrByDay[day], let hrv = hrvByDay[day] else { continue }

            let earlier = (1...max(baselineDays, 1)).compactMap { calendar.date(byAdding: .day, value: -$0, to: day) }
            let rhrHistory = earlier.compactMap { rhrByDay[$0] }
            let hrvHistory = earlier.compactMap { hrvByDay[$0] }
            let rhrBaseline = rhrHistory.count >= minBaselineDays ? Self.median(rhrHistory) : rhr
            let hrvBaseline = hrvHistory.count >= minBaselineDays ? Self.median(hrvHistory) : hrv

            result.append(RecoverySnapshot(
                date: day, sleepMinutes: Int(sleep.rounded()), restingHeartRate: Int(rhr.rounded()),
                hrvMs: Int(hrv.rounded()), restingHeartRateBaseline: Int(rhrBaseline.rounded()),
                hrvBaselineMs: Int(hrvBaseline.rounded()), isSimulated: isSimulated))
        }
        return result
    }

    // MARK: Per-day reductions

    private func sleepMinutesPerDay(_ intervals: [SleepInterval]) -> [Date: Double] {
        let sorted = intervals.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var merged: [SleepInterval] = []
        for interval in sorted {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1].end = max(last.end, interval.end)
            } else {
                merged.append(interval)
            }
        }
        var perDay: [Date: Double] = [:]
        for interval in merged {
            perDay[calendar.startOfDay(for: interval.end), default: 0] += interval.end.timeIntervalSince(interval.start) / 60
        }
        return perDay
    }

    private func latestPerDay(_ values: [DatedValue]) -> [Date: Double] {
        var latest: [Date: DatedValue] = [:]
        for v in values {
            let day = calendar.startOfDay(for: v.date)
            if let current = latest[day], current.date >= v.date { continue }
            latest[day] = v
        }
        return latest.mapValues(\.value)
    }

    private func meanPerDay(_ values: [DatedValue]) -> [Date: Double] {
        var sums: [Date: (sum: Double, count: Int)] = [:]
        for v in values {
            let day = calendar.startOfDay(for: v.date)
            sums[day, default: (0, 0)].sum += v.value
            sums[day, default: (0, 0)].count += 1
        }
        return sums.mapValues { $0.sum / Double($0.count) }
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}
