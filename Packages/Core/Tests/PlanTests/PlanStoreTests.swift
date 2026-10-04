import Contracts
import XCTest
@testable import Plan

final class PlanStoreTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ month: Int, _ dayOfMonth: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: dayOfMonth, hour: hour))!
    }

    // 2026-10-05 is a Monday.
    private let monday = (10, 5)

    private func file(_ name: String = "plan.json") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("forma-plan-\(UUID().uuidString)").appendingPathComponent(name)
    }

    private func store(_ url: URL?, now: Date? = nil, bootstrap: TrainingPlan? = nil) -> PlanStore {
        let moment = now ?? day(10, 5)
        return PlanStore(fileURL: url, calendar: calendar, now: { moment }, bootstrap: { bootstrap })
    }

    /// Four weeks from Monday 5.10, sessions on Monday, Wednesday and Friday (12 sessions, each with its own date).
    private lazy var plan: TrainingPlan =
        PlanScheduler.schedule(SampleData.plan, startingOn: day(10, 5, hour: 0), weeks: 4, calendar: calendar)

    // MARK: saving

    func testThePlanSurvivesARestart() throws {
        let url = file()
        var original = plan
        original.notices = [.offline]
        store(url).save(original)
        let again = store(url)
        XCTAssertEqual(again.templatePlan, original)
        XCTAssertEqual(again.templatePlan?.notices, [.offline])
    }

    func testTheSavedPlanNeverCarriesDone() {
        var finished = plan
        finished.sessions[0].status = .done
        let s = store(nil)
        s.save(finished)
        XCTAssertEqual(s.templatePlan?.sessions[0].status, .planned)
    }

    func testSavingReplacesThePlan() {
        let s = store(nil)
        s.save(plan)
        var other = plan
        other.sessions.removeLast()
        s.save(other)
        XCTAssertEqual(s.templatePlan?.sessions.count, plan.sessions.count - 1)
    }

    func testClearRemovesEverythingIncludingTheFile() {
        let url = file()
        let s = store(url)
        s.save(plan)
        s.recordCompletion(sessionId: plan.sessions[0].id)
        s.clear()
        XCTAssertNil(s.templatePlan)
        XCTAssertTrue(s.completions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertNil(store(url).templatePlan)
    }

    // MARK: first launch, older plans and broken files

    func testTheFirstLaunchTakesThePlanFromOnboardingAndSavesIt() {
        let url = file()
        XCTAssertEqual(store(url, bootstrap: plan).templatePlan, plan)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(store(url).templatePlan, plan, "the next launch needs no bootstrap")
    }

    func testAPlanWithoutDatesIsLaidOnTheCalendarFromToday() throws {
        // What an older version saved: one weekly pattern (Monday, Wednesday, Friday).
        let url = file()
        let laid = try XCTUnwrap(store(url, now: day(10, 7), bootstrap: SampleData.plan).templatePlan)
        XCTAssertTrue(laid.isDated)
        XCTAssertEqual(laid.weeks, PlanScheduler.defaultWeeks)
        XCTAssertEqual(laid.startDate, calendar.startOfDay(for: day(10, 7)))
        XCTAssertEqual(laid.chronological.first?.weekday, 3, "starts on Wednesday 7.10, today")
        XCTAssertEqual(store(url).templatePlan, laid, "and is saved that way")
    }

    func testSavingAPlanWithoutDatesLaysItOnTheCalendarToo() {
        let s = store(nil, now: day(10, 5))
        s.save(SampleData.plan)
        XCTAssertEqual(s.templatePlan?.isDated, true)
    }

    func testASavedPlanWinsOverTheBootstrap() {
        let url = file()
        var mine = plan
        mine.sessions.removeLast()
        store(url).save(mine)
        XCTAssertEqual(store(url, bootstrap: plan).templatePlan?.sessions.count, plan.sessions.count - 1)
    }

    func testNothingSavedAndNoBootstrapMeansNoPlan() async {
        let s = store(file())
        XCTAssertNil(s.templatePlan)
        let current = await s.currentPlan()
        let today = await s.todaySession()
        XCTAssertNil(current)
        XCTAssertNil(today)
    }

    func testABrokenFileFallsBackToTheBootstrapAndIsKeptAside() throws {
        let url = file()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let s = store(url, bootstrap: plan)
        XCTAssertEqual(s.templatePlan, plan)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.deletingPathExtension().appendingPathExtension("corrupt.json").path))
    }

    func testPlansSavedWithoutNoticesStillLoad() throws {
        // The file written by a version from before `notices` existed.
        let url = file()
        store(url).save(plan)
        let data = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: ",\"notices\":[]", with: "")
        try data.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(store(url).templatePlan?.sessions, plan.sessions)
    }

    // MARK: finished sessions

    func testAFinishedSessionIsDone() {
        let s = store(nil, now: day(monday.0, monday.1))
        s.save(plan)
        s.recordCompletion(sessionId: plan.sessions[0].id, date: day(monday.0, monday.1, hour: 18))
        let resolved = s.resolvedPlan()
        XCTAssertEqual(resolved?.sessions[0].status, .done)
        XCTAssertEqual(resolved?.sessions[1].status, .planned)
        XCTAssertEqual(s.templatePlan?.sessions[0].status, .planned, "the saved plan stays clean")
    }

    func testTheSameWeekdayNextWeekIsAnotherSession() {
        // Monday 5.10 is done; Monday 12.10 is a different session and is still to do.
        let s = store(nil, now: day(10, 12))
        s.save(plan)
        let mondays = plan.chronological.filter { $0.weekday == 1 }
        s.recordCompletion(sessionId: mondays[0].id, date: day(10, 5))
        let resolved = s.resolvedPlan()?.chronological.filter { $0.weekday == 1 }
        XCTAssertEqual(resolved?[0].status, .done)
        XCTAssertEqual(resolved?[1].status, .planned)
    }

    func testMarkingTwiceKeepsOneEntry() {
        let session = plan.sessions[0]
        let s = store(nil)
        s.save(plan)
        s.recordCompletion(sessionId: session.id, date: day(monday.0, monday.1), completedSets: 2, plannedSets: 4)
        s.recordCompletion(sessionId: session.id, date: day(monday.0, monday.1 + 2), completedSets: 4, plannedSets: 4)
        XCTAssertEqual(s.completions.count, 1)
        XCTAssertEqual(s.completions.first?.completedSets, 4)
    }

    func testTwoSessionsKeepTwoEntriesNewestFirst() {
        let s = store(nil)
        s.recordCompletion(sessionId: plan.sessions[0].id, date: day(10, 5))
        s.recordCompletion(sessionId: plan.sessions[1].id, date: day(10, 7))
        XCTAssertEqual(s.completions.count, 2)
        XCTAssertEqual(s.completions.first?.date, day(10, 7))
    }

    func testTakingBackDone() {
        let session = plan.sessions[0]
        let s = store(nil)
        s.save(plan)
        s.recordCompletion(sessionId: session.id, date: day(monday.0, monday.1))
        s.removeCompletion(sessionId: session.id)
        XCTAssertEqual(s.resolvedPlan()?.sessions[0].status, .planned)
    }

    func testFinishedSessionsOutliveAReplacedPlan() {
        let s = store(nil)
        s.save(plan)
        s.recordCompletion(sessionId: plan.sessions[0].id, date: day(monday.0, monday.1))
        s.save(plan)  // same sessions again (for example after a change of the plan)
        XCTAssertEqual(s.resolvedPlan()?.sessions[0].status, .done)
    }

    func testCompletionsSurviveARestartAndAreCapped() {
        let url = file()
        let first = store(url)
        first.recordCompletion(sessionId: UUID(), date: day(10, 5))
        XCTAssertEqual(store(url).completions.count, 1)
        for week in 0..<(PlanStore.maxCompletions + 20) {
            first.recordCompletion(sessionId: UUID(), date: day(10, 5).addingTimeInterval(Double(week) * 86_400))
        }
        XCTAssertEqual(first.completions.count, PlanStore.maxCompletions)
    }

    func testAnyPlanCanBeResolvedNotOnlyTheSavedOne() {
        let session = plan.sessions[1]
        let s = store(nil)
        s.recordCompletion(sessionId: session.id, date: day(monday.0, monday.1))
        XCTAssertEqual(s.resolved(plan).sessions[1].status, .done)
        XCTAssertEqual(s.resolved(plan).sessions[0].status, .planned)
    }

    // MARK: PlanProviding

    func testCurrentPlanComesWithDone() async {
        let s = store(nil)
        s.save(plan)
        s.recordCompletion(sessionId: plan.sessions[2].id, date: day(monday.0, monday.1))
        let current = await s.currentPlan()
        XCTAssertEqual(current?.sessions[2].status, .done)
    }

    func testTodaySessionIsTodaysThenTheNextThenNothingWhenThePlanRanOut() async {
        func today(_ month: Int, _ dayOfMonth: Int) async -> PlannedSession? {
            let s = store(nil, now: day(month, dayOfMonth))
            s.save(plan)  // Monday, Wednesday, Friday for four weeks: 5.10 to 1.11
            return await s.todaySession()
        }
        let onMonday = await today(10, 5)
        let tuesday = await today(10, 6)
        let saturday = await today(10, 10)
        let lastDay = await today(11, 2)
        let afterTheEnd = await today(11, 3)
        XCTAssertEqual(onMonday?.weekday, 1)
        XCTAssertEqual(tuesday?.weekday, 3, "no session on Tuesday: the next one is Wednesday")
        XCTAssertEqual(saturday?.weekday, 1, "after Friday comes Monday 12.10, not the first Monday of the plan")
        XCTAssertEqual(saturday.flatMap { $0.date }, calendar.startOfDay(for: day(10, 12)))
        XCTAssertNil(lastDay, "the last session was on Friday 30.10")
        XCTAssertNil(afterTheEnd)
    }

    func testAFinishedSessionOfTodayIsStillTodaysSession() async {
        let s = store(nil, now: day(monday.0, monday.1))
        s.save(plan)
        s.recordCompletion(sessionId: plan.sessions[0].id, date: day(monday.0, monday.1))
        let today = await s.todaySession()
        XCTAssertEqual(today?.weekday, 1)
        XCTAssertEqual(today?.status, .done)
    }

    func testParallelWritesDoNotCrashOrLoseTheStore() {
        let s = store(file())
        s.save(plan)
        DispatchQueue.concurrentPerform(iterations: 50) { index in
            if index % 2 == 0 { s.recordCompletion(sessionId: UUID(), date: day(10, 5)) } else { _ = s.resolvedPlan() }
        }
        XCTAssertEqual(s.completions.count, 25)
        XCTAssertEqual(s.templatePlan?.sessions.count, plan.sessions.count)
    }

    /// The screens refresh on this: every change of the saved data is reported, once per change, after the lock is released.
    func testEveryChangeIsReported() {
        let store = store(nil)
        let count = ChangeCounter()
        store.onChange = { count.hit() }
        let plan = SampleData.plan
        store.save(plan)
        XCTAssertEqual(count.value, 1)
        let session = plan.sessions[0].id
        store.recordCompletion(sessionId: session)
        XCTAssertEqual(count.value, 2)
        // Reading the store from the callback must not deadlock.
        store.onChange = { _ = store.completedSessionIds(); count.hit() }
        store.removeCompletion(sessionId: session)
        XCTAssertEqual(count.value, 3)
        store.clear()
        XCTAssertEqual(count.value, 4)
    }
}

private final class ChangeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var hits = 0
    func hit() { lock.lock(); hits += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return hits }
}
