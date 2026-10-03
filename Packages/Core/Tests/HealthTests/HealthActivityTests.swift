import XCTest
import Contracts
@testable import Health

final class HealthActivityTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 9))!

    func testNumbersAreFormattedTheMetricWay() {
        XCTAssertEqual(ActivityMetric.steps.formatted(8_432), "8\u{00A0}432")
        XCTAssertEqual(ActivityMetric.steps.formatted(950), "950")
        XCTAssertEqual(ActivityMetric.steps.formatted(12_000_000), "12\u{00A0}000\u{00A0}000")
        XCTAssertEqual(ActivityMetric.activeEnergy.formattedWithUnit(412.4), "412 kcal")
        XCTAssertEqual(ActivityMetric.distance.formattedWithUnit(5.26), "5,3 km")
        XCTAssertEqual(ActivityMetric.exercise.formattedWithUnit(34), "34 min")
        XCTAssertEqual(ActivityMetric.flights.formattedWithUnit(6), "6")
        XCTAssertEqual(ActivityMetric.steps.formattedWithUnit(8_432), "8\u{00A0}432")
    }

    func testEveryMetricHasTitleImageAndShortTitle() {
        for metric in ActivityMetric.allCases {
            XCTAssertFalse(metric.title.isEmpty)
            XCTAssertFalse(metric.shortTitle.isEmpty)
            XCTAssertFalse(metric.systemImage.isEmpty)
        }
        XCTAssertEqual(ActivityMetric.activeEnergy.shortTitle, "Kalorie")
        XCTAssertEqual(ActivityMetric.steps.shortTitle, "Kroki")
    }

    func testDailyActivityReadsEachMetricAndKnowsWhenItIsEmpty() {
        let day = DailyActivity(date: now, steps: 8_000, activeEnergyKcal: 400, distanceKm: 5.5, exerciseMinutes: 30,
                                flightsClimbed: 7)
        XCTAssertFalse(day.isEmpty)
        XCTAssertEqual(day.value(for: .steps), 8_000)
        XCTAssertEqual(day.value(for: .activeEnergy), 400)
        XCTAssertEqual(day.value(for: .distance), 5.5)
        XCTAssertEqual(day.value(for: .exercise), 30)
        XCTAssertEqual(day.value(for: .flights), 7)
        XCTAssertTrue(DailyActivity(date: now).isEmpty)
        XCTAssertNil(DailyActivity(date: now).value(for: .steps))
    }

    func testAverageSkipsDaysWithoutDataInsteadOfCountingZero() {
        let overview = HealthOverview(activity: [
            DailyActivity(date: now, steps: 6_000),
            DailyActivity(date: now.addingTimeInterval(-86_400)),
            DailyActivity(date: now.addingTimeInterval(-2 * 86_400), steps: 10_000),
        ])
        XCTAssertEqual(overview.average(of: .steps), 8_000)
        XCTAssertNil(overview.average(of: .distance))
        XCTAssertNil(HealthOverview().average(of: .steps))
    }

    func testHasDataLooksAtActivityAndRecovery() {
        XCTAssertFalse(HealthOverview().hasData)
        XCTAssertFalse(HealthOverview(activity: [DailyActivity(date: now)]).hasData)
        XCTAssertTrue(HealthOverview(activity: [DailyActivity(date: now, steps: 1)]).hasData)
        XCTAssertTrue(HealthOverview(recovery: [HealthDaySummary(date: now, sleepMinutes: 400)]).hasData)
    }

    func testSampleOverviewIsSimulatedNewestFirstAndComplete() {
        let overview = HealthOverview.sample(days: 7, now: now, calendar: calendar, recovery: [])
        XCTAssertTrue(overview.isSimulated)
        XCTAssertEqual(overview.activity.count, 7)
        XCTAssertEqual(overview.today?.date, calendar.startOfDay(for: now))
        XCTAssertEqual(overview.activity[1].date, calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)))
        XCTAssertTrue(overview.activity.allSatisfy { !$0.isEmpty && $0.flightsClimbed != nil })
        XCTAssertTrue(HealthOverview.sample(days: 0, now: now, calendar: calendar, recovery: []).activity.isEmpty)
    }
}
