import API
import Contracts
import XCTest
@testable import Coaching
import Plan

/// The tool calls the real model produced (Gemini, 4.10.2026) for a Sunday and a plan of Monday/Wednesday/Friday
/// sessions, run through the proposer: every one must land on the day the model named.
final class PlanChangeByDateToolTests: XCTestCase {
    private let calendar = TrainingPlan.calendar
    private func day(_ month: Int, _ dayOfMonth: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: dayOfMonth, hour: hour))!
    }

    private struct Plans: PlanProviding {
        let plan: TrainingPlan
        func currentPlan() async -> TrainingPlan? { plan }
        func todaySession() async -> PlannedSession? { plan.chronological.first }
    }

    private func proposer(today: Date) -> (PlanChangeProposer, TrainingPlan) {
        let plan = PlanScheduler.schedule(SampleData.plan, startingOn: day(10, 5), weeks: 4, calendar: calendar)
        let proposer = PlanChangeProposer(plan: Plans(plan: plan), catalog: SampleServices(),
                                          profile: { SampleData.profile }, now: { today })
        return (proposer, plan)
    }

    private func call(_ kind: String, date: String, newDate: String? = nil) -> JSONValue {
        var fields: [String: JSONValue] = ["kind": .string(kind), "date": .string(date), "reason": .string("Na prośbę.")]
        if let newDate { fields["newDate"] = .string(newDate) }
        return .object(fields)
    }

    func testMovingFridayToTuesday() async throws {
        let (proposer, plan) = proposer(today: day(10, 4))
        let output = await proposer.propose(call("move_session", date: "2026-10-09", newDate: "2026-10-06"))
        XCTAssertFalse(output.isError, output.content)
        let proposal = try XCTUnwrap(output.proposal)
        XCTAssertEqual(plan.sessions.first { $0.id == proposal.sessionId }?.date, calendar.startOfDay(for: day(10, 9)))
        XCTAssertEqual(proposal.newDate, calendar.startOfDay(for: day(10, 6)))
        XCTAssertTrue(proposal.summary.contains("z piątku (9 paź)") && proposal.summary.contains("na wtorek (6 paź)"), proposal.summary)
    }

    func testSkippingWednesdayNextWeek() async throws {
        let (proposer, plan) = proposer(today: day(10, 4))
        let output = await proposer.propose(call("skip_session", date: "2026-10-14"))
        XCTAssertFalse(output.isError, output.content)
        let proposal = try XCTUnwrap(output.proposal)
        XCTAssertEqual(plan.sessions.first { $0.id == proposal.sessionId }?.date, calendar.startOfDay(for: day(10, 14)))
    }

    func testMovingFridayThe16thToSaturday() async throws {
        let (proposer, _) = proposer(today: day(10, 4))
        let output = await proposer.propose(call("move_session", date: "2026-10-16", newDate: "2026-10-17"))
        XCTAssertFalse(output.isError, output.content)
        XCTAssertEqual(output.proposal?.newDate, calendar.startOfDay(for: day(10, 17)))
    }

    func testADayWithoutASessionGetsAnErrorWithTheDatesThatExist() async {
        let (proposer, _) = proposer(today: day(10, 4))
        let output = await proposer.propose(call("skip_session", date: "2026-10-06"))
        XCTAssertTrue(output.isError)
        XCTAssertTrue(output.content.contains("2026-10-07"), "the hint lists real dates: \(output.content)")
    }

    func testAGarbledDateIsAnErrorTheModelCanFix() async {
        let (proposer, _) = proposer(today: day(10, 4))
        let output = await proposer.propose(call("skip_session", date: "piątek"))
        XCTAssertTrue(output.isError)
        XCTAssertTrue(output.content.contains("RRRR-MM-DD"))
    }
}
