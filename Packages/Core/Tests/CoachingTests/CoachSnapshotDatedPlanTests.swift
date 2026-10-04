@testable import API
import Contracts
import XCTest
@testable import Coaching
import Plan

/// The coach sees the seven days from today of a plan that runs for weeks: each weekday once.
final class CoachSnapshotDatedPlanTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private struct Technique: TechniqueHistoryProviding {
        func results(limit: Int) async -> [TechniqueResult] { [] }
        func setSummaries(limit: Int) async -> [SetSummary] { [] }
    }

    func testTheSnapshotHoldsTheNextSevenDaysNotTheWholePlan() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!  // Wednesday
        let plan = PlanScheduler.schedule(SampleData.plan, startingOn: now, weeks: 4, calendar: calendar)
        let store = PlanStore(fileURL: nil, calendar: calendar, now: { now })
        store.save(plan)
        let builder = CoachSnapshotBuilder(plan: store, technique: Technique(), calendar: calendar, now: { now })
        let snapshot = await builder.snapshot(healthConsent: true)
        XCTAssertEqual(snapshot.today, 3)
        XCTAssertEqual(snapshot.week.map(\.weekday), [3, 5, 1], "Wed 14, Fri 16, Mon 19: in the order they happen")
        XCTAssertEqual(snapshot.nextSession?.weekday, 3)
        XCTAssertTrue(snapshot.nextSessionIsToday)
    }

    func testEverySessionAndTodayCarryTheirDate() async {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 12))!
        let plan = PlanScheduler.schedule(SampleData.plan, startingOn: now, weeks: 4, calendar: calendar)
        let store = PlanStore(fileURL: nil, calendar: calendar, now: { now })
        store.save(plan)
        let builder = CoachSnapshotBuilder(plan: store, technique: Technique(), calendar: calendar, now: { now })
        let snapshot = await builder.snapshot(healthConsent: true)
        XCTAssertEqual(snapshot.todayDate, "2026-10-14")
        XCTAssertEqual(snapshot.week.map(\.date), ["2026-10-14", "2026-10-16", "2026-10-19"])
        XCTAssertEqual(snapshot.nextSession?.date, "2026-10-14")
    }
}
