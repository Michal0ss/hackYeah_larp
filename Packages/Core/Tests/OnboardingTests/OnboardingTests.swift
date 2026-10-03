import XCTest
import Contracts
@testable import Onboarding

final class HealthHistoryTests: XCTestCase {
    private func answeredAllNo() -> HealthHistory {
        var h = HealthHistory()
        for q in ScreeningQuestion.allCases { h.answer(q, false) }
        return h
    }

    func testNothingProvidedIsIncompleteWithNothingToOmit() {
        let h = HealthHistory()
        XCTAssertEqual(h.result, .incomplete)
        XCTAssertTrue(h.omitTags.isEmpty)
        XCTAssertTrue(h.isEmpty)
    }

    func testEachAreaOmitsItsMovements() {
        func omit(_ areas: BodyArea...) -> [MovementTag] {
            var h = HealthHistory()
            areas.forEach { h.toggleInjury($0) }
            return h.omitTags
        }
        XCTAssertEqual(omit(.knee), [.jumps, .deepLunges])
        XCTAssertEqual(omit(.ankle), [.jumps])
        XCTAssertEqual(omit(.shoulder), [.overheadPress])
        XCTAssertEqual(omit(.back), [.barbellDeadlift])
        XCTAssertEqual(omit(.hip), [.deepSquats])
        XCTAssertEqual(omit(.elbow), [.loadedPushups])
        XCTAssertEqual(omit(.knee, .ankle), [.jumps, .deepLunges], "jumps only once")
        XCTAssertEqual(omit(.elbow, .shoulder, .knee), [.jumps, .deepLunges, .overheadPress, .loadedPushups], "stable order")
    }

    func testJointOrBoneAnswerOmitsJumpsOnlyWithoutInjuries() {
        var h = HealthHistory()
        h.answer(.jointOrBone, true)
        XCTAssertEqual(h.omitTags, [.jumps])
        h.toggleInjury(.shoulder)
        XCTAssertEqual(h.omitTags, [.overheadPress])
    }

    func testOnlySuggestingQuestionsCallForConsultation() {
        for question in ScreeningQuestion.allCases {
            var h = answeredAllNo()
            h.answer(question, true)
            if question.suggestsConsultation {
                XCTAssertEqual(h.result, .consult(omit: h.omitTags), "\(question)")
            } else {
                XCTAssertEqual(h.result, .adapt(omit: [.jumps]), "\(question) only adapts the plan")
            }
        }
        XCTAssertFalse(ScreeningQuestion.jointOrBone.suggestsConsultation)
    }

    func testScreeningResults() {
        XCTAssertEqual(answeredAllNo().result, .clear)

        var knee = answeredAllNo()
        knee.toggleInjury(.knee)
        XCTAssertEqual(knee.result, .adapt(omit: [.jumps, .deepLunges]))

        var partial = HealthHistory()
        partial.answer(.chestPain, false)
        XCTAssertEqual(partial.result, .incomplete)

        var yes = HealthHistory()
        yes.answer(.dizziness, true)
        XCTAssertEqual(yes.result, .consult(omit: []), "a yes is enough, even if the rest is unanswered")
    }

    func testNoConditionsAndConditionsExcludeEachOther() {
        var h = HealthHistory()
        h.selectNoConditions()
        XCTAssertEqual(h.conditionSummary, "Nic z powyższych")
        h.toggleCondition(.diabetes)
        XCTAssertFalse(h.noConditions)
        XCTAssertEqual(h.conditionSummary, "Cukrzyca")
        h.selectNoConditions()
        XCTAssertTrue(h.conditions.isEmpty)
        XCTAssertFalse(h.hasReportedCondition)
        XCTAssertEqual(HealthHistory().conditionSummary, "Nie podano")
    }

    func testSummaries() {
        var h = HealthHistory()
        XCTAssertEqual(h.injurySummary, "Nic nie zaznaczono")
        h.toggleInjury(.bark_or_shoulder)
        h.toggleInjury(.knee)
        h.injuryRecency = .mid
        XCTAssertEqual(h.injurySummary, "Kolano, Bark · 3–12 mies. temu")
    }

    func testCodableRoundTripKeepsUnansweredQuestions() throws {
        var h = HealthHistory()
        h.toggleInjury(.back)
        h.answer(.chestPain, false)
        h.answer(.dizziness, true)
        let decoded = try JSONDecoder().decode(HealthHistory.self, from: JSONEncoder().encode(h))
        XCTAssertEqual(decoded, h)
        XCTAssertNil(decoded.answer(for: .supervisedOnly))
        XCTAssertEqual(decoded.answer(for: .dizziness), true)
    }
}

private extension BodyArea {
    static var bark_or_shoulder: BodyArea { .shoulder }
}

final class OnboardingDraftTests: XCTestCase {
    func testDefaultsAreValidAndGearIsEmpty() {
        let draft = OnboardingDraft()
        XCTAssertTrue(OnboardingDraft.dayOptions.contains(draft.daysPerWeek))
        XCTAssertTrue(OnboardingDraft.minuteOptions.contains(draft.sessionMinutes))
        XCTAssertTrue(draft.gear.isEmpty)
    }

    func testOnlyOfferedValuesAreAccepted() {
        var draft = OnboardingDraft()
        draft.setDays(9)
        draft.setMinutes(10)
        XCTAssertEqual(draft.daysPerWeek, 4)
        XCTAssertEqual(draft.sessionMinutes, 45)
        draft.setDays(2)
        draft.setMinutes(75)
        XCTAssertEqual(draft.daysPerWeek, 2)
        XCTAssertEqual(draft.sessionMinutes, 75)
    }

    func testNoGearExcludesTheOthers() {
        var draft = OnboardingDraft()
        draft.toggleGear(.dumbbells)
        draft.toggleGear(.kettlebell)
        XCTAssertEqual(draft.gear, [.dumbbells, .kettlebell])
        draft.toggleGear(.none)
        XCTAssertEqual(draft.gear, [.none])
        draft.toggleGear(.gym)
        XCTAssertEqual(draft.gear, [.gym])
        draft.toggleGear(.gym)
        XCTAssertTrue(draft.gear.isEmpty)
        XCTAssertEqual(draft.resolvedGear, [.none], "nothing ticked means no equipment")
    }

    func testProfileCarriesChoicesAndDerivedRestrictions() {
        var draft = OnboardingDraft()
        draft.goal = .returnToMovement
        draft.level = .beginner
        draft.setDays(3)
        draft.setMinutes(60)
        draft.toggleGear(.kettlebell)
        draft.avoid = "  skoki  \n"
        draft.health.toggleInjury(.knee)
        let profile = draft.makeProfile()
        XCTAssertEqual(profile.goal, .returnToMovement)
        XCTAssertEqual(profile.level, .beginner)
        XCTAssertEqual(profile.daysPerWeek, 3)
        XCTAssertEqual(profile.sessionMinutes, 60)
        XCTAssertEqual(profile.equipment, .dumbbells)
        XCTAssertEqual(profile.gear, [.kettlebell])
        XCTAssertEqual(profile.avoid, "skoki")
        XCTAssertEqual(profile.avoidTags, [.jumps, .deepLunges])
        XCTAssertFalse(profile.easyStart)
    }

    func testEasyStartFollowsConsultationSignalOrReportedCondition() {
        var consult = OnboardingDraft()
        consult.health.answer(.chestPain, true)
        XCTAssertTrue(consult.makeProfile().easyStart)

        var condition = OnboardingDraft()
        condition.health.toggleCondition(.lungs)
        XCTAssertTrue(condition.makeProfile().easyStart)

        var clear = OnboardingDraft()
        clear.health.selectNoConditions()
        XCTAssertFalse(clear.makeProfile().easyStart)
    }

    /// Privacy guard: the profile is sent to the language model, so it must never carry the health history.
    func testProfileJSONHasNoHealthHistoryFields() throws {
        var draft = OnboardingDraft()
        draft.health.toggleInjury(.back)
        draft.health.toggleCondition(.diabetes)
        draft.health.answer(.chestPain, true)
        let data = try JSONEncoder().encode(draft.makeProfile())
        let keys = Set(try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys)
        XCTAssertEqual(keys, ["goal", "level", "daysPerWeek", "sessionMinutes", "equipment", "avoid", "gear", "avoidTags", "easyStart"])
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("diabetes"))
        XCTAssertFalse(text.contains("chestPain"))
        XCTAssertFalse(text.contains("injur"))
    }
}

final class OnboardingStepTests: XCTestCase {
    func testNumberingAndLabels() {
        XCTAssertEqual(OnboardingStep.goal.label, "Krok 1 z 6")
        XCTAssertEqual(OnboardingStep.appleHealth.label, "Krok 6 z 6")
        XCTAssertNil(OnboardingStep.generating.label)
        XCTAssertEqual(OnboardingStep.allCases.compactMap(\.number).count, OnboardingStep.numberedCount)
    }

    func testOrderAndSkippableSteps() {
        XCTAssertEqual(OnboardingStep.goal.next, .aboutYou)
        XCTAssertEqual(OnboardingStep.appleHealth.next, .generating)
        XCTAssertNil(OnboardingStep.generating.next)
        XCTAssertNil(OnboardingStep.goal.previous)
        XCTAssertEqual(OnboardingStep.allCases.filter { $0.skipTitle != nil }, [.medicalHistory, .screening])
    }
}

// MARK: - Model

private struct FakeHealth: HealthAuthorizing {
    var grants: Bool
    func requestAccess() async -> Bool { grants }
}

private final class FakeGenerator: PlanGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var failuresLeft: Int
    private var received: [UserProfile] = []

    init(failures: Int = 0) { failuresLeft = failures }

    var profiles: [UserProfile] { lock.lock(); defer { lock.unlock() }; return received }

    struct Failure: Error {}

    func generatePlan(for profile: UserProfile) async throws -> TrainingPlan {
        lock.lock()
        received.append(profile)
        let shouldFail = failuresLeft > 0
        if shouldFail { failuresLeft -= 1 }
        lock.unlock()
        if shouldFail { throw Failure() }
        return try await SampleServices().generatePlan(for: profile)
    }
}

@MainActor
final class OnboardingModelTests: XCTestCase {
    private func makeModel(grants: Bool = true, failures: Int = 0) -> (OnboardingModel, FakeGenerator) {
        let generator = FakeGenerator(failures: failures)
        let model = OnboardingModel(health: FakeHealth(grants: grants), generator: generator,
                                    minimumGenerationSeconds: 0, tickMilliseconds: 1)
        return (model, generator)
    }

    private func advance(_ model: OnboardingModel, to step: OnboardingStep) {
        while model.step != step {
            if model.step == .screening, !model.canAdvance { model.skip() } else { model.advance() }
            if model.step == .appleHealth, step != .appleHealth { break }
        }
    }

    func testWalksThroughTheSixSteps() {
        let (model, _) = makeModel()
        XCTAssertEqual(model.step, .goal)
        XCTAssertFalse(model.canGoBack)
        for expected in [OnboardingStep.aboutYou, .equipment, .medicalHistory] {
            model.advance()
            XCTAssertEqual(model.step, expected)
        }
        XCTAssertTrue(model.canGoBack)
        model.back()
        XCTAssertEqual(model.step, .equipment)
    }

    func testScreeningNeedsAllAnswersUnlessThereIsASignal() {
        let (model, _) = makeModel()
        advance(model, to: .screening)
        XCTAssertEqual(model.step, .screening)
        XCTAssertFalse(model.canAdvance)
        model.advance()
        XCTAssertEqual(model.step, .screening, "cannot pass with unanswered questions")

        model.draft.health.answer(.chestPain, true)
        XCTAssertTrue(model.canAdvance, "a yes already calls for caution, no need to answer the rest")
        model.advance()
        XCTAssertEqual(model.step, .appleHealth)
    }

    func testAnsweringEverythingUnlocksTheNextStep() {
        let (model, _) = makeModel()
        advance(model, to: .screening)
        for q in ScreeningQuestion.allCases { model.draft.health.answer(q, false) }
        XCTAssertTrue(model.canAdvance)
        XCTAssertEqual(model.screeningResult, .clear)
    }

    func testSkippingMedicalHistoryClearsWhatWasTicked() {
        let (model, _) = makeModel()
        advance(model, to: .medicalHistory)
        model.draft.health.toggleInjury(.knee)
        model.draft.health.toggleCondition(.diabetes)
        model.skip()
        XCTAssertEqual(model.step, .screening)
        XCTAssertTrue(model.draft.health.injuries.isEmpty)
        XCTAssertTrue(model.draft.health.conditions.isEmpty)
    }

    func testSkippingScreeningKeepsTheAnswersGiven() {
        let (model, _) = makeModel()
        advance(model, to: .screening)
        model.draft.health.answer(.dizziness, false)
        model.skip()
        XCTAssertEqual(model.step, .appleHealth)
        XCTAssertEqual(model.draft.health.answer(for: .dizziness), false)
    }

    func testSkipDoesNothingOnOtherSteps() {
        let (model, _) = makeModel()
        model.skip()
        XCTAssertEqual(model.step, .goal)
    }

    func testHealthAccessGrantedMovesToGeneration() async {
        let (model, _) = makeModel(grants: true)
        advance(model, to: .appleHealth)
        await model.requestHealthAccess()
        XCTAssertEqual(model.step, .generating)
        XCTAssertEqual(model.healthAccess, .granted)
        XCTAssertNil(model.healthAccessNotice)
        XCTAssertFalse(model.canGoBack, "no way back during generation")
    }

    func testHealthAccessDeniedStaysAndExplains() async {
        let (model, _) = makeModel(grants: false)
        advance(model, to: .appleHealth)
        await model.requestHealthAccess()
        XCTAssertEqual(model.step, .appleHealth)
        XCTAssertNotNil(model.healthAccessNotice)
        XCTAssertNil(model.healthAccess)
        model.useSampleHealthData()
        XCTAssertEqual(model.step, .generating)
        XCTAssertEqual(model.healthAccess, .sampleData)
    }

    func testGenerationBuildsPlanFromTheProfileAndFinishes() async throws {
        let (model, generator) = makeModel()
        model.draft.setDays(3)
        model.draft.health.toggleInjury(.knee)
        model.draft.health.answer(.chestPain, true)
        advance(model, to: .appleHealth)
        model.useSampleHealthData()
        await model.startGeneration()

        XCTAssertEqual(model.generation, .done)
        XCTAssertEqual(model.progress, 1)
        XCTAssertEqual(model.plan?.sessions.count, 3)
        XCTAssertTrue(model.generationStages.allSatisfy { $0.state == .done })

        let sent = try XCTUnwrap(generator.profiles.first)
        XCTAssertEqual(sent.avoidTags, [.jumps, .deepLunges])
        XCTAssertTrue(sent.easyStart)

        let result = try XCTUnwrap(model.makeResult())
        XCTAssertEqual(result.profile, sent)
        XCTAssertEqual(result.healthAccess, .sampleData)
        XCTAssertEqual(result.health.injuries, [.knee], "health history is kept for the phone, not for the profile")
    }

    func testFailureCanBeRetried() async {
        let (model, generator) = makeModel(failures: 1)
        advance(model, to: .appleHealth)
        model.useSampleHealthData()
        await model.startGeneration()
        guard case .failed = model.generation else { return XCTFail("expected failure, got \(model.generation)") }
        XCTAssertNil(model.makeResult())

        await model.retryGeneration()
        XCTAssertEqual(model.generation, .done)
        XCTAssertEqual(generator.profiles.count, 2)
        XCTAssertNotNil(model.makeResult())
    }

    func testResultIsNotAvailableBeforeGenerationFinishes() {
        let (model, _) = makeModel()
        XCTAssertNil(model.makeResult())
    }

    func testGenerationStagesFollowProgress() {
        func states(_ p: Double) -> [GenerationStage.State] {
            OnboardingModel.stages(progress: p, omit: [], easyStart: false).map(\.state)
        }
        XCTAssertEqual(states(0), [.current, .upcoming, .upcoming, .upcoming])
        XCTAssertEqual(states(0.31), [.done, .current, .upcoming, .upcoming])
        XCTAssertEqual(states(0.65), [.done, .done, .current, .upcoming])
        XCTAssertEqual(states(0.95), [.done, .done, .done, .current])
        XCTAssertEqual(states(1), [.done, .done, .done, .done])
    }

    func testStageDetailMentionsOmittedMovementsAndEasyStart() {
        let stages = OnboardingModel.stages(progress: 0.5, omit: [.jumps, .deepLunges], easyStart: true)
        XCTAssertEqual(stages[1].detail, "Pomijam: skoki, głębokie wykroki. Lżejszy start.")
        XCTAssertNil(stages[0].detail)
        XCTAssertNil(OnboardingModel.stages(progress: 0.5, omit: [], easyStart: false)[1].detail)
        XCTAssertEqual(OnboardingModel.stages(progress: 0.5, omit: [], easyStart: true)[1].detail, "Lżejszy start.")
    }

    func testGenerationSummary() async {
        let (model, _) = makeModel()
        XCTAssertEqual(model.generationSummary, "Dobieram ćwiczenia z katalogu do celu, poziomu i sprzętu.")
        model.draft.setDays(4)
        model.draft.setMinutes(45)
        model.draft.health.toggleInjury(.shoulder)
        advance(model, to: .appleHealth)
        model.useSampleHealthData()
        await model.startGeneration()
        XCTAssertEqual(model.generationSummary,
                       "Tydzień z 4 sesjami po 45 min, dopasowany do celu i sprzętu. Bez: wyciskanie nad głowę.")
    }
}

final class OnboardingStorageTests: XCTestCase {
    private func sampleResult() -> OnboardingResult {
        var draft = OnboardingDraft()
        draft.health.toggleInjury(.knee)
        draft.health.answer(.dizziness, false)
        let profile = draft.makeProfile()
        let plan = SamplePlanBuilder_forTests.plan(for: profile)
        return OnboardingResult(profile: profile, health: draft.health, plan: plan, healthAccess: .granted,
                                completedAt: Date(timeIntervalSince1970: 1_790_000_000))
    }

    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("forma-onboarding-\(UUID().uuidString)")
    }

    func testFileStorageRoundTrip() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = FileOnboardingStorage(directory: dir)
        XCTAssertNil(storage.load())

        let result = sampleResult()
        try storage.save(result)
        XCTAssertEqual(storage.load(), result)
    }

    func testHealthHistoryLivesInItsOwnFileAndCanBeDeleted() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = FileOnboardingStorage(directory: dir)
        let result = sampleResult()
        try storage.save(result)

        let profileJSON = try String(contentsOf: dir.appendingPathComponent("profile.json"), encoding: .utf8)
        XCTAssertFalse(profileJSON.contains("injuries"), "health history must not be in the profile file")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("health-history.json").path))

        try storage.deleteHealthHistory()
        let loaded = try XCTUnwrap(storage.load())
        XCTAssertEqual(loaded.profile, result.profile)
        XCTAssertEqual(loaded.plan, result.plan)
        XCTAssertTrue(loaded.health.isEmpty)
    }

    func testClearRemovesEverything() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storage = FileOnboardingStorage(directory: dir)
        try storage.save(sampleResult())
        try storage.clear()
        XCTAssertNil(storage.load())
        XCTAssertNoThrow(try storage.clear(), "clearing twice is fine")
    }

    func testInMemoryStorage() throws {
        let storage = InMemoryOnboardingStorage()
        XCTAssertNil(storage.load())
        let result = sampleResult()
        try storage.save(result)
        XCTAssertEqual(storage.load(), result)
        try storage.deleteHealthHistory()
        XCTAssertTrue(try XCTUnwrap(storage.load()).health.isEmpty)
        try storage.clear()
        XCTAssertNil(storage.load())
    }
}

/// `SamplePlanBuilder` is internal to Contracts, so tests go through the public service.
private enum SamplePlanBuilder_forTests {
    static func plan(for profile: UserProfile) -> TrainingPlan {
        var built: TrainingPlan?
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            built = try? await SampleServices().generatePlan(for: profile)
            semaphore.signal()
        }
        semaphore.wait()
        return built!
    }
}
