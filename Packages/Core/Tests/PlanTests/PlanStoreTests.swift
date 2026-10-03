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

    // 2026-10-05 is a Monday, 2026-10-11 the Sunday of that week, 2026-10-12 the next Monday.
    private let monday = (10, 5), sunday = (10, 11), nextMonday = (10, 12)

    private func file(_ name: String = "plan.json") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("forma-plan-\(UUID().uuidString)").appendingPathComponent(name)
    }

    private func store(_ url: URL?, now: Date? = nil, bootstrap: TrainingPlan? = nil) -> PlanStore {
        let moment = now ?? day(10, 5)
        return PlanStore(fileURL: url, calendar: calendar, now: { moment }, bootstrap: { bootstrap })
    }

    private var plan: TrainingPlan { SampleData.plan }  // sessions on Monday, Wednesday and Friday

    // MARK: saving

    func testThePlanSurvivesARestart() throws {
        let url = file()
        let original = TrainingPlan(createdAt: day(10, 1), source: .template, sessions: plan.sessions, notices: [.offline])
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
        XCTAssertEqual(s.templatePlan?.sessions.count, 2)
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

    // MARK: first launch and broken files

    func testTheFirstLaunchTakesThePlanFromOnboardingAndSavesIt() {
        let url = file()
        XCTAssertEqual(store(url, bootstrap: plan).templatePlan, plan)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(store(url).templatePlan, plan, "the next launch needs no bootstrap")
    }

    func testASavedPlanWinsOverTheBootstrap() {
        let url = file()
        var mine = plan
        mine.sessions.removeLast()
        store(url).save(mine)
        XCTAssertEqual(store(url, bootstrap: plan).templatePlan?.sessions.count, 2)
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
        let legacy = TrainingPlan(createdAt: day(10, 1), source: .ai, sessions: plan.sessions)
        store(url).save(legacy)
        let data = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: ",\"notices\":[]", with: "")
        try data.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(store(url).templatePlan?.sessions, plan.sessions)
    }

    // MARK: finished sessions are tied to a week

    func testAFinishedSessionIsDoneThisWeek() {
        let s = store(nil, now: day(monday.0, monday.1))
        s.save(plan)
        let monday = plan.sessions[0]
        s.recordCompletion(sessionId: monday.id, date: day(self.monday.0, self.monday.1, hour: 18))
        let resolved = s.resolvedPlan()
        XCTAssertEqual(resolved?.sessions[0].status, .done)
        XCTAssertEqual(resolved?.sessions[1].status, .planned)
        XCTAssertEqual(s.templatePlan?.sessions[0].status, .planned, "the saved pattern stays clean")
    }

    func testTheSameSessionIsNotDoneInTheNextWeek() {
        let finishedMonday = plan.sessions[0]
        let s = store(nil, now: day(nextMonday.0, nextMonday.1))
        s.save(plan)
        s.recordCompletion(sessionId: finishedMonday.id, date: day(monday.0, monday.1))
        XCTAssertEqual(s.resolvedPlan()?.sessions[0].status, .planned)
        XCTAssertEqual(s.resolvedPlan(on: day(monday.0, monday.1))?.sessions[0].status, .done, "still done in its own week")
    }

    func testTheWeekRunsFromMondayToSunday() {
        let session = plan.sessions[0]
        let s = store(nil)
        s.save(plan)
        s.recordCompletion(sessionId: session.id, date: day(monday.0, monday.1))
        XCTAssertTrue(s.completedSessionIds(weekOf: day(sunday.0, sunday.1, hour: 23)).contains(session.id))
        XCTAssertFalse(s.completedSessionIds(weekOf: day(nextMonday.0, nextMonday.1, hour: 0)).contains(session.id))
        XCTAssertFalse(s.completedSessionIds(weekOf: day(10, 4, hour: 23)).contains(session.id), "the Sunday before is another week")
    }

    func testMarkingTwiceInOneWeekKeepsOneEntry() {
        let session = plan.sessions[0]
        let s = store(nil)
        s.save(plan)
        s.recordCompletion(sessionId: session.id, date: day(monday.0, monday.1), completedSets: 2, plannedSets: 4)
        s.recordCompletion(sessionId: session.id, date: day(monday.0, monday.1 + 2), completedSets: 4, plannedSets: 4)
        XCTAssertEqual(s.completions.count, 1)
        XCTAssertEqual(s.completions.first?.completedSets, 4)
    }

    func testTheSameSessionOnTwoWeeksKeepsBoth() {
        let session = plan.sessions[0]
        let s = store(nil)
        s.recordCompletion(sessionId: session.id, date: day(monday.0, monday.1))
        s.recordCompletion(sessionId: session.id, date: day(nextMonday.0, nextMonday.1))
        XCTAssertEqual(s.completions.count, 2)
        XCTAssertEqual(s.completions.first?.date, day(nextMonday.0, nextMonday.1), "newest first")
    }

    func testTakingBackDone() {
        let session = plan.sessions[0]
        let s = store(nil)
        s.save(plan)
        s.recordCompletion(sessionId: session.id, date: day(monday.0, monday.1))
        s.removeCompletion(sessionId: session.id, weekOf: day(monday.0, monday.1))
        XCTAssertEqual(s.resolvedPlan()?.sessions[0].status, .planned)
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

    func testTodaySessionIsTodaysThenTheNextThenTheFirst() async {
        func today(_ date: (Int, Int)) async -> Int? {
            let s = store(nil, now: day(date.0, date.1))
            s.save(plan)  // Monday (1), Wednesday (3), Friday (5)
            return await s.todaySession()?.weekday
        }
        let todayIsMonday = await today(monday)
        let tuesday = await today((10, 6))
        let saturday = await today((10, 10))
        let sundayNight = await today(sunday)
        XCTAssertEqual(todayIsMonday, 1)
        XCTAssertEqual(tuesday, 3, "no session on Tuesday: the next one is Wednesday")
        XCTAssertEqual(saturday, 1, "after Friday the week starts again")
        XCTAssertEqual(sundayNight, 1)
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
        XCTAssertEqual(s.templatePlan?.sessions.count, 3)
    }
}
