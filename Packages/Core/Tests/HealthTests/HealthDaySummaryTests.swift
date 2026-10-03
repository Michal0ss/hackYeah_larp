import XCTest
import Contracts
@testable import Health

final class HealthDaySummaryTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return c
    }()
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 9))!
    private lazy var aggregator = RecoveryAggregator(calendar: calendar)

    private func at(_ daysAgo: Int, hour: Int) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    private func sleep(_ daysAgo: Int, hours: Double) -> SleepInterval {
        let end = at(daysAgo, hour: 7)
        return SleepInterval(start: end.addingTimeInterval(-hours * 3600), end: end)
    }

    // MARK: Aggregator

    func testSleepOnlyDayIsShownWithMissingNumbersNil() {
        let s = HealthSamples(sleep: [sleep(0, hours: 6 + 25.0 / 60)])
        let result = aggregator.summaries(from: s, days: 7, now: now)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].sleepMinutes, 385)
        XCTAssertNil(result[0].restingHeartRate)
        XCTAssertNil(result[0].hrvMs)
        XCTAssertNil(result[0].restingHeartRateBaseline)
        XCTAssertNil(result[0].snapshot, "incomplete: not for the rule engine")
        XCTAssertFalse(result[0].isEmpty)
    }

    func testSnapshotsStillNeedAllThreeNumbers() {
        let s = HealthSamples(sleep: [sleep(0, hours: 7)], restingHeartRate: [DatedValue(date: at(0, hour: 8), value: 56)])
        XCTAssertTrue(aggregator.snapshots(from: s, days: 7, now: now).isEmpty)
        XCTAssertEqual(aggregator.summaries(from: s, days: 7, now: now).count, 1)
    }

    func testNoDataNoSummaries() {
        XCTAssertTrue(aggregator.summaries(from: HealthSamples(), days: 7, now: now).isEmpty)
        XCTAssertTrue(aggregator.summaries(from: HealthSamples(sleep: [sleep(0, hours: 7)]), days: 0, now: now).isEmpty)
    }

    func testNewestFirstAndOnlyDaysWithData() {
        let s = HealthSamples(sleep: [sleep(0, hours: 7), sleep(2, hours: 6), sleep(5, hours: 8)])
        let result = aggregator.summaries(from: s, days: 7, now: now)
        XCTAssertEqual(result.map(\.sleepMinutes), [420, 360, 480])
        XCTAssertEqual(result.map(\.date), result.map(\.date).sorted(by: >))
    }

    func testBaselinesPerMetricFromEarlierDays() {
        var s = HealthSamples()
        for d in 1...5 { s.restingHeartRate.append(DatedValue(date: at(d, hour: 8), value: 55)) }
        s.restingHeartRate.append(DatedValue(date: at(0, hour: 8), value: 60))
        s.hrv.append(DatedValue(date: at(0, hour: 4), value: 40)) // HRV has no history: baseline = own value
        let today = aggregator.summaries(from: s, days: 1, now: now)[0]
        XCTAssertEqual(today.restingHeartRate, 60)
        XCTAssertEqual(today.restingHeartRateBaseline, 55)
        XCTAssertEqual(today.restingHeartRateDelta, 5)
        XCTAssertEqual(today.hrvBaselineMs, 40)
        XCTAssertEqual(today.hrvDeltaPercent, 0)
    }

    func testSummariesAndSnapshotsAgreeOnCompleteDays() {
        var s = HealthSamples()
        for d in 0..<10 {
            s.sleep.append(sleep(d, hours: 7))
            s.restingHeartRate.append(DatedValue(date: at(d, hour: 8), value: d == 0 ? 61 : 56))
            s.hrv.append(DatedValue(date: at(d, hour: 4), value: d == 0 ? 38 : 46))
        }
        let snaps = aggregator.snapshots(from: s, days: 10, now: now)
        let sums = aggregator.summaries(from: s, days: 10, now: now)
        XCTAssertEqual(sums.compactMap(\.snapshot), snaps)
        XCTAssertEqual(snaps[0].restingHeartRateBaseline, 56)
        XCTAssertEqual(snaps[0].hrvBaselineMs, 46)
    }

    // MARK: Summary

    func testDeltasAndTexts() {
        let d = HealthDaySummary(date: now, sleepMinutes: 340, restingHeartRate: 61, hrvMs: 38,
                                 restingHeartRateBaseline: 56, hrvBaselineMs: 46)
        XCTAssertEqual(d.sleepText, "5 h 40 min")
        XCTAssertEqual(d.restingHeartRateDelta, 5)
        XCTAssertEqual(d.hrvDeltaPercent, -17)
        XCTAssertEqual(HealthDaySummary(date: now, sleepMinutes: 420).sleepText, "7 h")
        XCTAssertNil(HealthDaySummary(date: now).sleepText)
        XCTAssertNil(HealthDaySummary(date: now, hrvMs: 40).hrvDeltaPercent, "no baseline, no delta")
        XCTAssertTrue(HealthDaySummary(date: now).isEmpty)
    }

    func testFromSnapshotKeepsEverythingIncludingTheSimulatedFlag() {
        let snapshot = SampleData.recovery[0]
        let summary = HealthDaySummary(snapshot)
        XCTAssertEqual(summary.snapshot, snapshot)
        XCTAssertTrue(summary.isSimulated)
    }
}
