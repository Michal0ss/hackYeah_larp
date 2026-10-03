import Contracts
import XCTest
@testable import Plan

final class PlanEditorTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: dayOfMonth, hour: 12))!
    }

    private var profile: UserProfile {
        var p = SampleData.profile
        p.equipment = .gym
        p.level = .intermediate
        p.easyStart = false
        p.avoidTags = []
        return p
    }

    // Monday, Wednesday, Friday for 4 weeks from Monday 5.10; "today" is Monday 5.10.
    private lazy var plan: TrainingPlan = {
        var week = SampleData.plan
        // Two Monday sessions with the same title so the scope is visible.
        week.sessions[0].title = "Nogi"
        return PlanScheduler.schedule(week, startingOn: day(10, 5), weeks: 4, calendar: calendar)
    }()

    private func editor(today: Date? = nil) -> PlanEditor {
        let moment = today ?? day(10, 5)
        return PlanEditor(catalog: bundledCatalog, profile: profile, calendar: calendar, now: { moment })
    }

    private var firstMonday: PlannedSession { plan.chronological.first { $0.title == "Nogi" }! }
    private var mondays: [PlannedSession] { plan.chronological.filter { $0.title == "Nogi" } }

    // MARK: prescription and scope

    func testChangingSetsAndRepsOfOneSession() throws {
        let exercise = firstMonday.exercises[0].exerciseId
        let result = try editor().apply(.setPrescription(exerciseId: exercise, sets: 5, repsMin: 6, repsMax: 8, restSeconds: 90),
                                        to: firstMonday.id, in: plan)
        XCTAssertEqual(result.changedSessionIds, [firstMonday.id])
        let item = result.plan.sessions.first { $0.id == firstMonday.id }!.exercises[0]
        XCTAssertEqual([item.sets, item.repsMin, item.repsMax, item.restSeconds], [5, 6, 8, 90])
        XCTAssertEqual(result.plan.sessions.filter { $0.id != firstMonday.id }, plan.sessions.filter { $0.id != firstMonday.id })
    }

    func testThisAndFollowingTouchesLaterSessionsOnly() throws {
        let second = mondays[1]
        let exercise = second.exercises[0].exerciseId
        let result = try editor().apply(.setPrescription(exerciseId: exercise, sets: 2, repsMin: nil, repsMax: nil, restSeconds: nil),
                                        to: second.id, scope: .thisAndFollowing, in: plan)
        XCTAssertEqual(result.changedSessionIds.count, mondays.count - 1, "the first Monday stays as it was")
        XCTAssertFalse(result.changedSessionIds.contains(mondays[0].id))
        XCTAssertEqual(result.plan.sessions.first { $0.id == mondays[0].id }, mondays[0])
        XCTAssertTrue(result.summary.contains("\(mondays.count - 1) sesjach"))
    }

    func testFinishedAndSkippedSessionsAreLeftAloneByThisAndFollowing() throws {
        var marked = plan
        let index = marked.sessions.firstIndex { $0.id == mondays[2].id }!
        marked.sessions[index].status = .skipped
        let exercise = mondays[1].exercises[0].exerciseId
        let result = try editor().apply(.setPrescription(exerciseId: exercise, sets: 2, repsMin: nil, repsMax: nil, restSeconds: nil),
                                        to: mondays[1].id, scope: .thisAndFollowing, in: marked)
        XCTAssertFalse(result.changedSessionIds.contains(mondays[2].id))
    }

    func testNumbersOutOfRangeAreRefused() {
        let e = firstMonday.exercises[0].exerciseId
        func edit(_ sets: Int? = nil, _ min: Int? = nil, _ max: Int? = nil, _ rest: Int? = nil) throws {
            _ = try editor().apply(.setPrescription(exerciseId: e, sets: sets, repsMin: min, repsMax: max, restSeconds: rest),
                                   to: firstMonday.id, in: plan)
        }
        XCTAssertThrowsError(try edit(0))
        XCTAssertThrowsError(try edit(9))
        XCTAssertThrowsError(try edit(nil, 0, nil))
        XCTAssertThrowsError(try edit(nil, 10, 8), "min above max")
        XCTAssertThrowsError(try edit(nil, nil, nil, 601))
        XCTAssertNoThrow(try edit(1, 1, 1, 0))
    }

    // MARK: exercises

    func testSwapUsesOnlyCatalogExercisesThatFit() throws {
        let from = firstMonday.exercises[0].exerciseId
        XCTAssertThrowsError(try editor().apply(.swapExercise(from: from, to: "levitation"), to: firstMonday.id, in: plan)) {
            XCTAssertEqual($0 as? PlanChangeError, .replacementNotInCatalog)
        }
        var noGear = profile
        noGear.equipment = .none
        let strict = PlanEditor(catalog: bundledCatalog, profile: noGear, calendar: calendar, now: { self.day(10, 5) })
        XCTAssertThrowsError(try strict.apply(.swapExercise(from: from, to: "back_squat"), to: firstMonday.id, in: plan)) {
            XCTAssertEqual($0 as? PlanChangeError, .replacementNotSuitable)
        }
    }

    func testAddingAndRemovingAnExercise() throws {
        let present = Set(firstMonday.exercises.map(\.exerciseId))
        let candidate = bundledCatalog.first { !present.contains($0.id) && ($0.timed ?? false) == false && $0.equipment == .none }!
        let added = try editor().apply(.addExercise(candidate.id), to: firstMonday.id, in: plan)
        let session = added.plan.sessions.first { $0.id == firstMonday.id }!
        XCTAssertEqual(session.exercises.last?.exerciseId, candidate.id)
        XCTAssertEqual(session.exercises.last?.sets, firstMonday.exercises[0].sets, "same sets as the others")
        let removed = try editor().apply(.removeExercise(candidate.id), to: firstMonday.id, in: added.plan)
        XCTAssertEqual(removed.plan.sessions.first { $0.id == firstMonday.id }?.exercises, firstMonday.exercises)
    }

    func testTheLastExerciseCannotBeRemoved() {
        var single = plan
        single.sessions[0].exercises = [single.sessions[0].exercises[0]]
        XCTAssertThrowsError(try editor().apply(.removeExercise(single.sessions[0].exercises[0].exerciseId),
                                                to: single.sessions[0].id, in: single)) {
            XCTAssertEqual($0 as? PlanChangeError, .lastExercise)
        }
    }

    func testAnExerciseCannotBeAddedTwiceOrOverTheLimit() throws {
        XCTAssertThrowsError(try editor().apply(.addExercise(firstMonday.exercises[0].exerciseId), to: firstMonday.id, in: plan)) {
            XCTAssertEqual($0 as? PlanChangeError, .replacementAlreadyInSession)
        }
        var full = plan
        let index = full.sessions.firstIndex { $0.id == firstMonday.id }!
        let others = bundledCatalog.filter { $0.equipment == .none }.prefix(PlanLimits.maxExercises)
        full.sessions[index].exercises = others.map { PlanEditor.defaultPrescription(for: $0, like: []) }
        let extra = bundledCatalog.first { $0.equipment == .none && !others.contains($0) }!
        XCTAssertThrowsError(try editor().apply(.addExercise(extra.id), to: firstMonday.id, in: full)) {
            XCTAssertEqual($0 as? PlanChangeError, .tooManyExercises)
        }
    }

    func testReorderingExercises() throws {
        let ids = firstMonday.exercises.map(\.exerciseId)
        let result = try editor().apply(.moveExercise(ids[0], toIndex: 2), to: firstMonday.id, in: plan)
        let after = result.plan.sessions.first { $0.id == firstMonday.id }!.exercises.map(\.exerciseId)
        XCTAssertEqual(after[2], ids[0])
        XCTAssertEqual(Set(after), Set(ids))
    }

    // MARK: days

    func testMovingASessionToAFreeDay() throws {
        // Tuesday 6.10 is free.
        let result = try editor().apply(.moveSession(to: day(10, 6)), to: firstMonday.id, in: plan)
        let moved = result.plan.sessions.first { $0.id == firstMonday.id }!
        XCTAssertEqual(moved.date, calendar.startOfDay(for: day(10, 6)))
        XCTAssertEqual(moved.weekday, 2)
    }

    func testADayWithASessionThePastAndTheTimeAfterThePlanAreRefused() {
        let id = mondays[1].id  // Monday 12.10
        func move(to date: Date) -> PlanChangeError? {
            do { _ = try editor().apply(.moveSession(to: date), to: id, in: plan); return nil } catch { return error as? PlanChangeError }
        }
        XCTAssertEqual(move(to: day(10, 14)), .dayTaken, "Wednesday 14.10 has a session")
        XCTAssertEqual(move(to: day(10, 4)), .outsidePlan, "yesterday")
        XCTAssertEqual(move(to: day(11, 3)), .outsidePlan, "after the four weeks")
        XCTAssertNil(move(to: day(10, 13)))
    }

    func testSkippingAndRestoring() throws {
        let skipped = try editor().apply(.skip, to: firstMonday.id, in: plan)
        XCTAssertEqual(skipped.plan.sessions.first { $0.id == firstMonday.id }?.status, .skipped)
        // A skipped session cannot be edited, only restored.
        XCTAssertThrowsError(try editor().apply(.addExercise("x"), to: firstMonday.id, in: skipped.plan)) {
            XCTAssertEqual($0 as? PlanChangeError, .sessionSkipped)
        }
        let back = try editor().apply(.restore, to: firstMonday.id, in: skipped.plan)
        XCTAssertEqual(back.plan.sessions.first { $0.id == firstMonday.id }?.status, .planned)
        // And a session that was not skipped has nothing to restore.
        XCTAssertThrowsError(try editor().apply(.restore, to: firstMonday.id, in: plan))
    }

    func testAFinishedSessionCannotBeEdited() {
        var finished = plan
        finished.sessions[0].status = .done
        XCTAssertThrowsError(try editor().apply(.skip, to: finished.sessions[0].id, in: finished)) {
            XCTAssertEqual($0 as? PlanChangeError, .sessionDone)
        }
    }

    func testRemovingAllFollowingSessionsOfADay() throws {
        let result = try editor().apply(.removeSession, to: mondays[1].id, scope: .thisAndFollowing, in: plan)
        XCTAssertEqual(result.plan.sessions.filter { $0.title == "Nogi" }.count, 1, "only the first Monday is left")
    }

    // MARK: own sessions

    func testAddingASessionOfYourOwn() throws {
        let ids = firstMonday.exercises.prefix(2).map(\.exerciseId)
        // Thursday 8.10 is free.
        let result = try editor().addSession(on: day(10, 8), title: "  Dodatkowa  ", exerciseIds: Array(ids), in: plan)
        let added = result.plan.sessions.first { $0.id == result.changedSessionIds[0] }!
        XCTAssertEqual(added.title, "Dodatkowa")
        XCTAssertEqual(added.weekday, 4)
        XCTAssertEqual(added.exercises.map(\.exerciseId), ids)
        XCTAssertEqual(result.plan.sessions.count, plan.sessions.count + 1)
        XCTAssertThrowsError(try editor().addSession(on: day(10, 7), title: "X", exerciseIds: ids, in: plan), "7.10 has a session")
        XCTAssertThrowsError(try editor().addSession(on: day(10, 8), title: "", exerciseIds: ids, in: plan))
        XCTAssertThrowsError(try editor().addSession(on: day(10, 8), title: "X", exerciseIds: [], in: plan))
    }
}

/// The coach's "skip a session" proposal.
final class PlanChangeSkipTests: XCTestCase {
    func testSkipIsProposedAppliedAndUndone() throws {
        let changer = PlanChanger(catalog: bundledCatalog, profile: SampleData.profile)
        let plan = SampleData.plan
        let proposal = try changer.propose(kind: .skipSession, weekday: 3, exerciseId: nil, replacementExerciseId: nil,
                                           newWeekday: nil, reason: "Brak czasu", in: plan)
        XCTAssertTrue(proposal.summary.hasPrefix("Pomiń sesję"))
        let applied = try changer.apply(proposal, to: plan)
        XCTAssertEqual(applied.plan.sessions.first { $0.id == proposal.sessionId }?.status, .skipped)
        // Nothing else can be done to a skipped session.
        XCTAssertThrowsError(try changer.propose(kind: .lighterSession, weekday: 3, exerciseId: nil, replacementExerciseId: nil,
                                                 newWeekday: nil, reason: nil, in: applied.plan))
        let undone = try changer.undo(applied.proposal, in: applied.plan)
        XCTAssertEqual(undone.plan.sessions.first { $0.id == proposal.sessionId }?.status, .planned)
    }

    func testASkippedSessionIsNotTheNextOne() {
        var plan = SampleData.plan
        let monday = plan.sessions.firstIndex { $0.weekday == 1 }!
        plan.sessions[monday].status = .skipped
        let calendar = TrainingPlan.calendar
        let onMonday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12))!
        XCTAssertEqual(plan.sessionOnOrAfter(onMonday, calendar: calendar)?.weekday, 3)
        XCTAssertEqual(plan.sessionOnOrAfter(onMonday, includeSkipped: true, calendar: calendar)?.weekday, 1)
    }
}
