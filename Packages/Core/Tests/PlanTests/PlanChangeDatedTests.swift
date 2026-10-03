import Contracts
import XCTest
@testable import Plan

/// The coach talks in weekdays; the plan has dates. A weekday means the next such day within a week from now.
final class PlanChangeDatedTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: dayOfMonth, hour: 12))!
    }

    // Monday, Wednesday and Friday for four weeks from Monday 5.10.
    private lazy var plan = PlanScheduler.schedule(SampleData.plan, startingOn: day(10, 5), weeks: 4, calendar: calendar)

    private func changer(today: Date) -> PlanChanger {
        PlanChanger(catalog: SampleData.catalog, profile: SampleData.profile, calendar: calendar, now: { today })
    }

    func testAWeekdayMeansTheNextSuchDayNotTheFirstOneInThePlan() throws {
        // On Tuesday 13.10 "Wednesday" is 14.10, not 7.10.
        let proposal = try changer(today: day(10, 13)).propose(kind: .lighterSession, weekday: 3, exerciseId: nil,
                                                               replacementExerciseId: nil, newWeekday: nil, reason: nil, in: plan)
        let target = try XCTUnwrap(plan.sessions.first { $0.id == proposal.sessionId })
        XCTAssertEqual(target.date, calendar.startOfDay(for: day(10, 14)))
    }

    func testAChangeTouchesOnlyThatDay() throws {
        let c = changer(today: day(10, 5))
        let proposal = try c.propose(kind: .lighterSession, weekday: 1, exerciseId: nil, replacementExerciseId: nil,
                                     newWeekday: nil, reason: nil, in: plan)
        let result = try c.apply(proposal, to: plan)
        let before = Dictionary(uniqueKeysWithValues: plan.sessions.map { ($0.id, $0.exercises) })
        let changed = result.plan.sessions.filter { before[$0.id] != $0.exercises }
        XCTAssertEqual(changed.count, 1)
        XCTAssertEqual(changed.first?.id, proposal.sessionId)
    }

    func testMovingASessionChangesItsDateWithinTheWeek() throws {
        // Monday 5.10 moves to Tuesday: 6.10.
        let c = changer(today: day(10, 5))
        let proposal = try c.propose(kind: .moveSession, weekday: 1, exerciseId: nil, replacementExerciseId: nil,
                                     newWeekday: 2, reason: nil, in: plan)
        let result = try c.apply(proposal, to: plan)
        let moved = try XCTUnwrap(result.plan.sessions.first { $0.id == proposal.sessionId })
        XCTAssertEqual(moved.weekday, 2)
        XCTAssertEqual(moved.date, calendar.startOfDay(for: day(10, 6)))
        // And back.
        let undone = try c.undo(result.proposal, in: result.plan)
        XCTAssertEqual(undone.plan.sessions.first { $0.id == proposal.sessionId }?.date, calendar.startOfDay(for: day(10, 5)))
    }

    func testADayWithASessionIsTakenOnThatDateOnly() throws {
        // Wednesday 7.10 has a session; Wednesday 14.10 too, but moving to "Wednesday" means 7.10 only.
        let c = changer(today: day(10, 5))
        XCTAssertThrowsError(try c.propose(kind: .moveSession, weekday: 1, exerciseId: nil, replacementExerciseId: nil,
                                           newWeekday: 3, reason: nil, in: plan)) {
            XCTAssertEqual($0 as? PlanChangeError, .dayTaken)
        }
    }

    func testAPlanWithoutDatesWorksAsBefore() throws {
        let c = changer(today: day(10, 5))
        let proposal = try c.propose(kind: .moveSession, weekday: 1, exerciseId: nil, replacementExerciseId: nil,
                                     newWeekday: 2, reason: nil, in: SampleData.plan)
        XCTAssertEqual(try c.apply(proposal, to: SampleData.plan).plan.sessions.first { $0.id == proposal.sessionId }?.weekday, 2)
    }
}
