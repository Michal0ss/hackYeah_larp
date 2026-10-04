@testable import API
import Content
import Contracts
import XCTest
@testable import Plan

// MARK: shared

let bundledCatalog = ContentRepository(cacheDirectory: nil).exercises

func bundledTemplates() throws -> PlanTemplates {
    try XCTUnwrap(PlanTemplates.bundled(), "plan_templates.json is not bundled")
}

/// What the backend built for one profile (Fixtures/generate.py).
struct FixturePlan: Decodable {
    struct Exercise: Decodable, Equatable {
        var exerciseId: String
        var sets: Int
        var repsMin: Int
        var repsMax: Int
        var restSeconds: Int
        var tempo: TempoSpec?
    }

    struct Session: Decodable, Equatable {
        var weekday: Int
        var title: String
        var exercises: [Exercise]
    }

    var profile: UserProfile
    var sessions: [Session]
}

func loadFixtures() throws -> [FixturePlan] {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "template_plans", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode([FixturePlan].self, from: Data(contentsOf: url))
}

func describe(_ p: UserProfile) -> String {
    "\(p.goal.rawValue)/\(p.level.rawValue)/\(p.daysPerWeek)d/\(p.sessionMinutes)min/\(p.equipment.rawValue)/avoid=\(p.avoidTags.map(\.rawValue))/easy=\(p.easyStart)"
}

// MARK: the Swift builder equals the backend's

final class TemplatePlanParityTests: XCTestCase {
    func testEveryProfileGetsTheSamePlanAsFromTheBackend() throws {
        let builder = TemplatePlanBuilder(templates: try bundledTemplates(), catalog: bundledCatalog)
        let fixtures = try loadFixtures()
        XCTAssertGreaterThanOrEqual(fixtures.count, 90)
        for fixture in fixtures {
            let plan = try XCTUnwrap(builder.build(for: fixture.profile), describe(fixture.profile))
            let built = plan.sessions.map { session in
                FixturePlan.Session(weekday: session.weekday, title: session.title, exercises: session.exercises.map {
                    FixturePlan.Exercise(exerciseId: $0.exerciseId, sets: $0.sets, repsMin: $0.repsMin, repsMax: $0.repsMax,
                                         restSeconds: $0.restSeconds, tempo: $0.tempo)
                })
            }
            XCTAssertEqual(built, fixture.sessions, "differs from the backend for \(describe(fixture.profile))")
            XCTAssertEqual(plan.source, .template)
        }
    }

    func testEveryBuiltPlanPassesTheValidator() throws {
        let templates = try bundledTemplates()
        let builder = TemplatePlanBuilder(templates: templates, catalog: bundledCatalog)
        for fixture in try loadFixtures() {
            let plan = try XCTUnwrap(builder.build(for: fixture.profile))
            XCTAssertEqual(PlanValidator.validate(plan, profile: fixture.profile, catalog: bundledCatalog, templates: templates), [],
                           describe(fixture.profile))
        }
    }

    func testAvoidedMovementsNeverAppear() throws {
        let builder = TemplatePlanBuilder(templates: try bundledTemplates(), catalog: bundledCatalog)
        var profile = SampleData.profile
        profile.avoidTags = [.deepSquats, .deepLunges, .jumps]
        let plan = try XCTUnwrap(builder.build(for: profile))
        for planned in plan.sessions.flatMap(\.exercises) {
            let tags = bundledCatalog.first { $0.id == planned.exerciseId }?.movementTags ?? []
            XCTAssertTrue(Set(tags).isDisjoint(with: profile.avoidTags), planned.exerciseId)
        }
    }

    func testBuildingIsDeterministicExceptForIdsAndDate() throws {
        let builder = TemplatePlanBuilder(templates: try bundledTemplates(), catalog: bundledCatalog)
        let a = try XCTUnwrap(builder.build(for: SampleData.profile))
        let b = try XCTUnwrap(builder.build(for: SampleData.profile))
        XCTAssertEqual(a.sessions.map { $0.exercises.map(\.exerciseId) }, b.sessions.map { $0.exercises.map(\.exerciseId) })
    }

    func testNoCatalogGivesSessionsWithoutExercisesWhichTheValidatorCatches() throws {
        let templates = try bundledTemplates()
        let plan = try XCTUnwrap(TemplatePlanBuilder(templates: templates, catalog: []).build(for: SampleData.profile))
        XCTAssertTrue(plan.sessions.allSatisfy { $0.exercises.isEmpty })
        XCTAssertTrue(PlanValidator.validate(plan, profile: SampleData.profile, catalog: [], templates: templates).contains(.badExerciseCount))
    }

    func testTemplatesWithoutThisGoalGiveNoPlan() throws {
        var templates = try bundledTemplates()
        templates.goals[SampleData.profile.goal.rawValue] = nil
        XCTAssertNil(TemplatePlanBuilder(templates: templates, catalog: bundledCatalog).build(for: SampleData.profile))
    }

    func testTemplatesFileDecodes() throws {
        let templates = try bundledTemplates()
        XCTAssertEqual(Set(templates.goals.keys), Set(TrainingGoal.allCases.map(\.rawValue)))
        XCTAssertEqual(templates.exercisesPerSession(forMinutes: 10), templates.exercisesPerSession(forMinutes: 30))
        XCTAssertEqual(templates.exercisesPerSession(forMinutes: 200), templates.exercisesPerSession(forMinutes: 90))
        XCTAssertNil(PlanTemplates.decode(Data("nonsense".utf8)))
    }
}

// MARK: the validator

final class PlanValidatorTests: XCTestCase {
    private let profile = SampleData.profile  // 3 days, dumbbells, intermediate, strength
    private var templates: PlanTemplates!

    override func setUpWithError() throws { templates = try bundledTemplates() }

    private func good() throws -> TrainingPlan {
        try XCTUnwrap(TemplatePlanBuilder(templates: templates, catalog: bundledCatalog).build(for: profile))
    }

    private func issues(_ plan: TrainingPlan, profile: UserProfile? = nil) -> [PlanIssue] {
        PlanValidator.validate(plan, profile: profile ?? self.profile, catalog: bundledCatalog, templates: templates)
    }

    func testAGoodPlanHasNoIssues() throws {
        XCTAssertEqual(issues(try good()), [])
    }

    func testWrongNumberOfSessions() throws {
        var plan = try good()
        plan.sessions.removeLast()
        XCTAssertEqual(issues(plan), [.wrongSessionCount])
    }

    func testDuplicateAndImpossibleWeekdays() throws {
        var plan = try good()
        plan.sessions[1].weekday = plan.sessions[0].weekday
        XCTAssertTrue(issues(plan).contains(.duplicateWeekday))
        plan = try good()
        plan.sessions[0].weekday = 9
        XCTAssertTrue(issues(plan).contains(.badWeekday))
    }

    func testExerciseCountAndRepeats() throws {
        var plan = try good()
        plan.sessions[0].exercises = []
        XCTAssertTrue(issues(plan).contains(.badExerciseCount))
        plan = try good()
        plan.sessions[0].exercises.append(plan.sessions[0].exercises[0])
        XCTAssertTrue(issues(plan).contains(.repeatedExercise))
    }

    func testUnknownExercise() throws {
        var plan = try good()
        plan.sessions[0].exercises[0].exerciseId = "levitation"
        XCTAssertEqual(issues(plan), [.unknownExercise])
    }

    func testEquipmentTheUserLacks() throws {
        var plan = try good()
        plan.sessions[0].exercises[0].exerciseId = "back_squat"  // gym only
        XCTAssertTrue(issues(plan).contains(.equipmentNotAvailable))
    }

    func testLevelTooHigh() throws {
        var beginner = profile
        beginner.level = .beginner
        var plan = try XCTUnwrap(TemplatePlanBuilder(templates: templates, catalog: bundledCatalog).build(for: beginner))
        plan.sessions[0].exercises[0].exerciseId = "romanian_deadlift"  // intermediate
        XCTAssertTrue(issues(plan, profile: beginner).contains(.levelTooHigh))
    }

    func testReturnToMovementForcesTheEasyLevel() throws {
        var returning = profile
        returning.goal = .returnToMovement
        var plan = try XCTUnwrap(TemplatePlanBuilder(templates: templates, catalog: bundledCatalog).build(for: returning))
        plan.sessions[0].exercises[0].exerciseId = "romanian_deadlift"
        XCTAssertTrue(issues(plan, profile: returning).contains(.levelTooHigh))
    }

    func testAvoidedMovement() throws {
        var avoiding = profile
        avoiding.avoidTags = [.deepSquats]
        var plan = try XCTUnwrap(TemplatePlanBuilder(templates: templates, catalog: bundledCatalog).build(for: avoiding))
        plan.sessions[0].exercises[0].exerciseId = "squat"
        XCTAssertTrue(issues(plan, profile: avoiding).contains(.avoidedMovement))
    }

    func testSetsAndRepsLimits() throws {
        var plan = try good()
        plan.sessions[0].exercises[0].sets = 9
        XCTAssertTrue(issues(plan).contains(.tooManySets))
        plan = try good()
        plan.sessions[0].exercises[0].sets = 0
        XCTAssertTrue(issues(plan).contains(.badSets))
        plan = try good()
        plan.sessions[0].exercises[0].repsMin = 12
        plan.sessions[0].exercises[0].repsMax = 8
        XCTAssertTrue(issues(plan).contains(.badRepRange))
        plan = try good()
        plan.sessions[0].exercises[0].repsMax = 80
        XCTAssertTrue(issues(plan).contains(.tooManyReps))
    }

    func testTimedExerciseNeedsSeconds() throws {
        var plan = try good()
        plan.sessions[0].exercises[0] = PlannedExercise(exerciseId: "plank", sets: 3, repsMin: 3, repsMax: 5, restSeconds: 30)
        XCTAssertTrue(issues(plan).contains(.badDuration))
    }
}

// MARK: the generator

struct FakeBackend: PlanBackend {
    var answer: @Sendable () async throws -> PlanGenerateResponse
    func generatePlan(for profile: UserProfile) async throws -> PlanGenerateResponse { try await answer() }
}

struct FixedCatalog: ExerciseCatalogProviding {
    var exercises: [ExerciseItem] = bundledCatalog
}

final class PlanSchedulerTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: dayOfMonth, hour: 15))!
    }

    // SampleData.plan: Monday, Wednesday and Friday. 2026-10-05 is a Monday.
    private func schedule(from start: Date, weeks: Int = 8) -> TrainingPlan {
        PlanScheduler.schedule(SampleData.plan, startingOn: start, weeks: weeks, calendar: calendar)
    }

    func testEverySessionGetsItsDateAndWeekday() {
        let plan = schedule(from: day(10, 5), weeks: 2)
        XCTAssertEqual(plan.sessions.count, 6)
        XCTAssertTrue(plan.isDated)
        for session in plan.sessions {
            XCTAssertEqual(TrainingPlan.isoWeekday(of: try! XCTUnwrap(session.date), calendar: calendar), session.weekday)
        }
        XCTAssertEqual(plan.chronological.compactMap(\.date).map { calendar.component(.day, from: $0) }, [5, 7, 9, 12, 14, 16])
    }

    func testThePlanStartsToday_NotInThePast() {
        // Thursday 8.10: this week's Monday and Wednesday are over.
        let plan = schedule(from: day(10, 8), weeks: 2)
        XCTAssertEqual(plan.chronological.first?.date, calendar.startOfDay(for: day(10, 9)))
        XCTAssertEqual(plan.startDate, calendar.startOfDay(for: day(10, 8)))
    }

    func testThePlanRunsForExactlyTheWeeksAsked() {
        // Thursday 8.10 + 2 weeks = up to and including Wednesday 21.10.
        let plan = schedule(from: day(10, 8), weeks: 2)
        XCTAssertEqual(plan.chronological.compactMap(\.date).map { calendar.component(.day, from: $0) }, [9, 12, 14, 16, 19, 21])
        XCTAssertEqual(plan.weeks, 2)
        XCTAssertTrue(plan.hasEnded(on: day(10, 22), calendar: calendar))
        XCTAssertFalse(plan.hasEnded(on: day(10, 21), calendar: calendar))
    }

    func testEverySessionIsItsOwnWithItsOwnId() {
        let plan = schedule(from: day(10, 5))
        XCTAssertEqual(Set(plan.sessions.map(\.id)).count, plan.sessions.count)
        XCTAssertTrue(plan.sessions.allSatisfy { $0.status == .planned })
    }

    func testEveryFourthWeekIsLighter() {
        let plan = schedule(from: day(10, 5))
        let sets = plan.chronological.filter { $0.weekday == 1 }.map { $0.exercises[0].sets }  // one per week
        let normal = SampleData.plan.sessions.first { $0.weekday == 1 }!.exercises[0].sets
        XCTAssertEqual(sets.count, 8)
        XCTAssertEqual(sets[0], normal)
        XCTAssertEqual(sets[3], normal - 1, "the 4th week")
        XCTAssertEqual(sets[7], normal - 1, "the 8th week")
        XCTAssertEqual(sets[4], normal)
        XCTAssertNotNil(plan.chronological.filter { $0.weekday == 1 }[3].adaptationNote)
        XCTAssertNil(plan.chronological[0].adaptationNote)
    }

    func testAWeekWindowHasEachWeekdayOnce() throws {
        let plan = schedule(from: day(10, 5))
        for offset in 0..<20 {
            let from = calendar.date(byAdding: .day, value: offset, to: day(10, 5))!
            let weekdays = plan.window(from: from, calendar: calendar).map(\.weekday)
            XCTAssertEqual(Set(weekdays).count, weekdays.count)
        }
    }

    func testReadingByDate() {
        let plan = schedule(from: day(10, 5), weeks: 2)
        XCTAssertEqual(plan.session(on: day(10, 7), calendar: calendar)?.weekday, 3)
        XCTAssertNil(plan.session(on: day(10, 8), calendar: calendar))
        XCTAssertEqual(plan.sessionOnOrAfter(day(10, 8), calendar: calendar)?.weekday, 5)
        XCTAssertNil(plan.sessionOnOrAfter(day(10, 17), calendar: calendar), "nothing after the last session")
        XCTAssertEqual(plan.week(containing: day(10, 14), calendar: calendar).count, 3)
        XCTAssertEqual(plan.sessionsPerWeek, 3)
    }

    func testAPlanWithoutDatesReadsAsBefore() {
        let pattern = SampleData.plan
        XCTAssertFalse(pattern.isDated)
        XCTAssertEqual(pattern.window(from: day(10, 5)).count, 3)
        XCTAssertEqual(pattern.sessionOnOrAfter(day(10, 6), calendar: calendar)?.weekday, 3)
        XCTAssertFalse(pattern.hasEnded(on: day(12, 1)))
    }

    func testTheDatedPlanSurvivesEncoding() throws {
        let plan = schedule(from: day(10, 5))
        let again = try JSONDecoder().decode(TrainingPlan.self, from: JSONEncoder().encode(plan))
        XCTAssertEqual(again, plan)
    }
}

final class PlanGeneratorTests: XCTestCase {
    private let profile = SampleData.profile  // has free text in `avoid`
    private var templates: PlanTemplates!

    override func setUpWithError() throws { templates = try bundledTemplates() }

    private func plan(source: PlanSource = .ai, for profile: UserProfile? = nil) throws -> TrainingPlan {
        var plan = try XCTUnwrap(TemplatePlanBuilder(templates: templates, catalog: bundledCatalog).build(for: profile ?? self.profile))
        plan.source = source
        return plan
    }

    private func generator(deadline: TimeInterval = 5, templates: PlanTemplates?? = .none,
                           _ answer: @escaping @Sendable () async throws -> PlanGenerateResponse) -> PlanGenerator {
        PlanGenerator(backend: FakeBackend(answer: answer), catalog: FixedCatalog(), templates: templates ?? self.templates,
                      deadline: deadline)
    }

    /// The first seven days of a dated plan, as the weekly pattern they came from: weekday → exercises.
    private func firstWeek(_ plan: TrainingPlan) throws -> [Int: [PlannedExercise]] {
        XCTAssertTrue(plan.isDated)
        let start = try XCTUnwrap(plan.startDate)
        return Dictionary(uniqueKeysWithValues: plan.window(from: start).map { ($0.weekday, $0.exercises) })
    }

    /// The first week as an undated plan, for the validator that checks one week.
    private func weekPlan(_ plan: TrainingPlan) throws -> TrainingPlan {
        var week = plan
        week.sessions = plan.window(from: try XCTUnwrap(plan.startDate)).map { var s = $0; s.date = nil; return s }
        return week
    }

    func testAValidPlanFromTheBackendIsKept() async throws {
        let fromAI = try plan()
        let result = try await generator { PlanGenerateResponse(plan: fromAI, warnings: []) }.generatePlan(for: profile)
        XCTAssertEqual(try firstWeek(result), Dictionary(uniqueKeysWithValues: fromAI.sessions.map { ($0.weekday, $0.exercises) }))
        XCTAssertEqual(result.weeks, PlanScheduler.defaultWeeks)
        XCTAssertEqual(result.source, .ai)
        XCTAssertEqual(result.notices, [])
    }

    func testServerWarningsBecomeNoticesAndAreNotRepeated() async throws {
        let fromServer = try plan(source: .template)
        let warnings = ["ai_unavailable", "avoid_text_not_applied", "ai_unavailable", "ai_mock", "something_new"]
        let result = try await generator { PlanGenerateResponse(plan: fromServer, warnings: warnings) }.generatePlan(for: profile)
        XCTAssertEqual(result.notices, [.aiUnavailable, .avoidTextNotApplied])
        XCTAssertEqual(try firstWeek(result), Dictionary(uniqueKeysWithValues: fromServer.sessions.map { ($0.weekday, $0.exercises) }))
    }

    func testAPlanThatFailsTheChecksIsReplacedByTheLocalTemplate() async throws {
        var bad = try plan()
        bad.sessions[0].exercises[0].exerciseId = "levitation"
        let result = try await generator { PlanGenerateResponse(plan: bad, warnings: []) }.generatePlan(for: profile)
        XCTAssertEqual(result.source, .template)
        XCTAssertEqual(result.notices, [.aiInvalidPlan, .avoidTextNotApplied])
        XCTAssertEqual(PlanValidator.validate(try weekPlan(result), profile: profile, catalog: bundledCatalog, templates: templates), [])
    }

    func testEquipmentTheUserLacksIsCaughtOnThePhoneToo() async throws {
        var noGear = profile
        noGear.equipment = .none
        noGear.avoid = ""
        var bad = try plan(for: noGear)
        bad.sessions[0].exercises[0].exerciseId = "back_squat"
        let result = try await generator { PlanGenerateResponse(plan: bad, warnings: []) }.generatePlan(for: noGear)
        XCTAssertEqual(result.notices, [.aiInvalidPlan])
        XCTAssertFalse(result.sessions.flatMap(\.exercises).contains { $0.exerciseId == "back_squat" })
    }

    func testNoConnectionBuildsThePlanOnThePhone() async throws {
        let result = try await generator { throw APIError.transport("offline") }.generatePlan(for: profile)
        XCTAssertEqual(result.source, .template)
        XCTAssertEqual(result.notices, [.offline, .avoidTextNotApplied])
        XCTAssertEqual(result.sessionsPerWeek, profile.daysPerWeek)
        XCTAssertEqual(PlanValidator.validate(try weekPlan(result), profile: profile, catalog: bundledCatalog, templates: templates), [])
    }

    func testNoBackendConfiguredIsTreatedAsOffline() async throws {
        let result = try await generator { throw APIError.notConfigured }.generatePlan(for: profile)
        XCTAssertEqual(result.notices.first, .offline)
    }

    func testServerErrorsMeanTheAIWasUnavailable() async throws {
        let error = APIError.server(ServerError(code: "internal_error", message: "boom", requestId: nil), status: 500, retryAfter: nil)
        let result = try await generator { throw error }.generatePlan(for: profile)
        XCTAssertEqual(result.notices.first, .aiUnavailable)
        let garbled = try await generator { throw APIError.invalidResponse("not json") }.generatePlan(for: profile)
        XCTAssertEqual(garbled.notices.first, .aiUnavailable)
    }

    func testNoFreeTextMeansNoFreeTextNotice() async throws {
        var plain = profile
        plain.avoid = "   "
        let result = try await generator { throw APIError.transport("offline") }.generatePlan(for: plain)
        XCTAssertEqual(result.notices, [.offline])
    }

    func testASlowBackendDoesNotKeepTheUserWaiting() async throws {
        let started = Date()
        let result = try await generator(deadline: 0.1) {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return PlanGenerateResponse(plan: try self.plan(), warnings: [])
        }.generatePlan(for: profile)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
        XCTAssertEqual(result.notices.first, .aiUnavailable)
        XCTAssertEqual(result.source, .template)
    }

    func testCancellingStopsInsteadOfQuietlyBuildingAPlan() async throws {
        let generator = generator {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return PlanGenerateResponse(plan: try self.plan(), warnings: [])
        }
        let task = Task { try await generator.generatePlan(for: profile) }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a cancelled generation must not produce a plan")
        } catch is CancellationError {
        } catch {
            XCTFail("\(error)")
        }
    }

    func testWithoutTemplatesTheSamplePlanStillGivesAPlan() async throws {
        let generator = PlanGenerator(backend: FakeBackend { throw APIError.transport("offline") }, catalog: FixedCatalog(),
                                      templates: nil, deadline: 5)
        let result = try await generator.generatePlan(for: profile)
        XCTAssertEqual(result.sessionsPerWeek, profile.daysPerWeek)
        XCTAssertEqual(result.notices.first, .offline)
    }

    func testAnEmptyCatalogStillGivesAPlan() async throws {
        let generator = PlanGenerator(backend: FakeBackend { throw APIError.transport("offline") },
                                      catalog: FixedCatalog(exercises: []), templates: templates, deadline: 5)
        let result = try await generator.generatePlan(for: profile)
        XCTAssertFalse(result.sessions.isEmpty)
    }

    func testOfflinePlanRespectsAvoidedMovements() async throws {
        var careful = profile
        careful.avoidTags = [.deepSquats, .deepLunges]
        let result = try await generator { throw APIError.transport("offline") }.generatePlan(for: careful)
        for planned in result.sessions.flatMap(\.exercises) {
            let tags = bundledCatalog.first { $0.id == planned.exerciseId }?.movementTags ?? []
            XCTAssertTrue(Set(tags).isDisjoint(with: careful.avoidTags), planned.exerciseId)
        }
    }

    func testTheNoticeForAnErrorFollowsItsKind() {
        XCTAssertEqual(PlanGenerator.notice(for: APIError.transport("x")), .offline)
        XCTAssertEqual(PlanGenerator.notice(for: APIError.notConfigured), .offline)
        XCTAssertEqual(PlanGenerator.notice(for: APIError.invalidResponse("x")), .aiUnavailable)
        XCTAssertEqual(PlanGenerator.notice(for: URLError(.timedOut)), .aiUnavailable)
    }
}
