import XCTest
import Contracts
@testable import Health

final class RecoveryAggregatorTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 9))!
    private lazy var aggregator = RecoveryAggregator(calendar: calendar)

    private func at(_ daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    /// A night that ends on the morning of `daysAgo`: 23:00 the evening before to `wakeHour:00`.
    private func night(_ daysAgo: Int, hours: Double) -> SleepInterval {
        let end = at(daysAgo, hour: 7)
        return SleepInterval(start: end.addingTimeInterval(-hours * 3600), end: end)
    }

    /// Full data for `daysAgo...(daysAgo + count - 1)`.
    private func history(from daysAgo: Int = 0, count: Int, sleepHours: Double = 7.5, rhr: Double = 56, hrv: Double = 46) -> HealthSamples {
        var s = HealthSamples()
        for d in daysAgo..<(daysAgo + count) {
            s.sleep.append(night(d, hours: sleepHours))
            s.restingHeartRate.append(DatedValue(date: at(d, hour: 8), value: rhr))
            s.hrv.append(DatedValue(date: at(d, hour: 4), value: hrv))
        }
        return s
    }

    private func merged(_ a: HealthSamples, _ b: HealthSamples) -> HealthSamples {
        HealthSamples(sleep: a.sleep + b.sleep, restingHeartRate: a.restingHeartRate + b.restingHeartRate, hrv: a.hrv + b.hrv)
    }

    func testNoSamplesNoSnapshots() {
        XCTAssertTrue(aggregator.snapshots(from: HealthSamples(), days: 7, now: now).isEmpty)
        XCTAssertTrue(aggregator.snapshots(from: history(count: 3), days: 0, now: now).isEmpty)
    }

    func testOneDaySummary() {
        let result = aggregator.snapshots(from: history(count: 1, sleepHours: 5 + 40.0 / 60, rhr: 61, hrv: 38), days: 7, now: now)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].date, calendar.startOfDay(for: now))
        XCTAssertEqual(result[0].sleepMinutes, 340)
        XCTAssertEqual(result[0].restingHeartRate, 61)
        XCTAssertEqual(result[0].hrvMs, 38)
        XCTAssertFalse(result[0].isSimulated)
    }

    func testNewestFirstAndDaysLimit() {
        let result = aggregator.snapshots(from: history(count: 10), days: 4, now: now)
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result.map(\.date), result.map(\.date).sorted(by: >))
        XCTAssertEqual(result.first?.date, calendar.startOfDay(for: now))
    }

    func testOverlappingSleepIntervalsAreNotCountedTwice() {
        // Two sources report the same night, one split in stages.
        var s = history(count: 1)
        s.sleep = [
            SleepInterval(start: at(1, hour: 23), end: at(0, hour: 7)),
            SleepInterval(start: at(1, hour: 23, minute: 30), end: at(0, hour: 3)),
            SleepInterval(start: at(0, hour: 3), end: at(0, hour: 7)),
        ]
        XCTAssertEqual(aggregator.snapshots(from: s, days: 1, now: now)[0].sleepMinutes, 8 * 60)
    }

    func testNightBelongsToTheMorningItEndedOn() {
        var s = history(count: 2)
        s.sleep = [SleepInterval(start: at(2, hour: 23), end: at(1, hour: 6, minute: 30))]
        let result = aggregator.snapshots(from: s, days: 3, now: now)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].date, calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: now)!))
        XCTAssertEqual(result[0].sleepMinutes, 450)
    }

    func testNapIsAddedToTheDay() {
        var s = history(count: 1, sleepHours: 7)
        s.sleep.append(SleepInterval(start: at(0, hour: 14), end: at(0, hour: 14, minute: 30)))
        XCTAssertEqual(aggregator.snapshots(from: s, days: 1, now: now)[0].sleepMinutes, 450)
    }

    func testHrvIsMeanOfTheDayAndRestingHeartRateIsTheLatest() {
        var s = history(count: 1)
        s.hrv = [DatedValue(date: at(0, hour: 2), value: 30), DatedValue(date: at(0, hour: 4), value: 40), DatedValue(date: at(0, hour: 5), value: 50)]
        s.restingHeartRate = [DatedValue(date: at(0, hour: 9), value: 60), DatedValue(date: at(0, hour: 6), value: 50)]
        let r = aggregator.snapshots(from: s, days: 1, now: now)[0]
        XCTAssertEqual(r.hrvMs, 40)
        XCTAssertEqual(r.restingHeartRate, 60)
    }

    func testBaselineIsMedianOfEarlierDaysAndExcludesTheDay() {
        // Today is an outlier (HRV 20); earlier 14 days are 40-ish with one extreme day.
        var s = history(from: 1, count: 14, hrv: 46)
        s.hrv.removeAll { $0.date < at(5, hour: 23) && $0.date > at(6, hour: 0) }
        s.hrv.append(DatedValue(date: at(5, hour: 5), value: 200)) // extreme day, median must ignore it
        let today = history(count: 1, sleepHours: 5, rhr: 64, hrv: 20)
        let r = aggregator.snapshots(from: merged(s, today), days: 1, now: now)[0]
        XCTAssertEqual(r.hrvMs, 20)
        XCTAssertEqual(r.hrvBaselineMs, 46)
        XCTAssertEqual(r.restingHeartRateBaseline, 56)
        XCTAssertEqual(r.restingHeartRate - r.restingHeartRateBaseline, 8)
    }

    func testTooLittleHistoryMeansNoFalseSignal() {
        let samples = merged(history(from: 1, count: 2), history(count: 1, sleepHours: 5, rhr: 70, hrv: 20))
        let r = aggregator.snapshots(from: samples, days: 1, now: now)[0]
        XCTAssertEqual(r.hrvBaselineMs, r.hrvMs)
        XCTAssertEqual(r.restingHeartRateBaseline, r.restingHeartRate)
        XCTAssertEqual(r.hrvDeltaRatio, 0)
    }

    func testDayWithMissingMetricIsSkipped() {
        var s = history(count: 3)
        s.hrv.removeAll { calendar.isDate($0.date, inSameDayAs: at(1, hour: 4)) }
        let result = aggregator.snapshots(from: s, days: 3, now: now)
        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(result.contains { calendar.isDate($0.date, inSameDayAs: at(1, hour: 4)) })
    }

    func testIgnoresZeroLengthSleep() {
        var s = history(count: 1, sleepHours: 7)
        s.sleep.append(SleepInterval(start: at(0, hour: 10), end: at(0, hour: 10)))
        XCTAssertEqual(aggregator.snapshots(from: s, days: 1, now: now)[0].sleepMinutes, 420)
    }

    func testIsSimulatedFlagIsPassedThrough() {
        XCTAssertTrue(aggregator.snapshots(from: history(count: 1), days: 1, now: now, isSimulated: true)[0].isSimulated)
    }

    func testMedian() {
        XCTAssertEqual(RecoveryAggregator.median([3, 1, 2]), 2)
        XCTAssertEqual(RecoveryAggregator.median([4, 1, 2, 3]), 2.5)
        XCTAssertEqual(RecoveryAggregator.median([]), 0)
    }
}
