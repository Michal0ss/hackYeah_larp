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
        XCTAssertEqual(templates.exercisesPerSession(forMinutes: 200), templates.exercisesPerSession(forMinutes: 75))
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

    func testAValidPlanFromTheBackendIsKept() async throws {
        let fromAI = try plan()
        let result = try await generator { PlanGenerateResponse(plan: fromAI, warnings: []) }.generatePlan(for: profile)
        XCTAssertEqual(result, fromAI)
        XCTAssertEqual(result.source, .ai)
        XCTAssertEqual(result.notices, [])
    }

    func testServerWarningsBecomeNoticesAndAreNotRepeated() async throws {
        let fromServer = try plan(source: .template)
        let warnings = ["ai_unavailable", "avoid_text_not_applied", "ai_unavailable", "ai_mock", "something_new"]
        let result = try await generator { PlanGenerateResponse(plan: fromServer, warnings: warnings) }.generatePlan(for: profile)
        XCTAssertEqual(result.notices, [.aiUnavailable, .avoidTextNotApplied])
        XCTAssertEqual(result.sessions, fromServer.sessions)
    }

    func testAPlanThatFailsTheChecksIsReplacedByTheLocalTemplate() async throws {
        var bad = try plan()
        bad.sessions[0].exercises[0].exerciseId = "levitation"
        let result = try await generator { PlanGenerateResponse(plan: bad, warnings: []) }.generatePlan(for: profile)
        XCTAssertEqual(result.source, .template)
        XCTAssertEqual(result.notices, [.aiInvalidPlan, .avoidTextNotApplied])
        XCTAssertEqual(PlanValidator.validate(result, profile: profile, catalog: bundledCatalog, templates: templates), [])
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
        XCTAssertEqual(result.sessions.count, profile.daysPerWeek)
        XCTAssertEqual(PlanValidator.validate(result, profile: profile, catalog: bundledCatalog, templates: templates), [])
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
        XCTAssertEqual(result.sessions.count, profile.daysPerWeek)
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
