import SwiftUI
import Observation
import Contracts
import Insights
import Onboarding
import Plan

/// In-memory app state. It starts on sample data (marked as simulated in the UI).
/// Owners replace the pieces with real sources: Wiktor (recovery, check-in, recommendation),
/// Maciek (profile, plan), Bartek (technique results).
@Observable
final class AppStore {
    /// Service implementations. Sample ones until the owners plug in the real ones (App/Services/AppServices.swift).
    var services = AppServices()

    var profile: UserProfile = SampleData.profile
    var plan: TrainingPlan = PlanScheduler.schedule(SampleData.plan, startingOn: Date())
    /// Bumped when newer content arrives from the backend, so screens that read `catalog` refresh.
    private(set) var contentRevision = 0
    var catalog: [ExerciseItem] { _ = contentRevision; return services.catalog.exercises }
    var recovery: [RecoverySnapshot] = SampleData.recovery
    var checkIn: CheckIn? = SampleData.checkIn
    var lastTechnique: TechniqueResult? = SampleData.technique
    var recommendation: DailyRecommendation = SampleData.recommendation {
        didSet { recommendationText = EngineText.make(for: recommendation) }
    }
    /// Wording of today's recommendation: the phone's own text first, the model's text when it arrives and passes
    /// the checks. The decision itself always comes from `recommendation`.
    private(set) var recommendationText = EngineText.make(for: SampleData.recommendation)
    @ObservationIgnored private var textTask: Task<Void, Never>?

    // MARK: Onboarding

    /// False until the first-run flow has been completed (or skipped with `-skip-onboarding` in debug builds).
    private(set) var onboardingCompleted = false
    /// Health history from onboarding. Stays on the phone; only `profile.avoidTags` and `easyStart` go further.
    private(set) var healthHistory = HealthHistory()
    private(set) var healthAccess: HealthAccessChoice?
    /// True when the onboarding result could not be written to disk (the app keeps working in memory).
    private(set) var onboardingSaveFailed = false
    @ObservationIgnored private let onboardingStorage: OnboardingStoring

    init(onboardingStorage: OnboardingStoring = FileOnboardingStorage.default) {
        self.onboardingStorage = onboardingStorage
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-reset-onboarding") {
            try? onboardingStorage.clear()
            services.planStore.clear()
        }
        #endif
        if let saved = onboardingStorage.load() {
            apply(saved)
            onboardingCompleted = true
        }
        #if DEBUG
        if arguments.contains("-skip-onboarding") { onboardingCompleted = true }
        #endif
    }

    /// Called when the user taps "Przejdź do Dziś" at the end of onboarding.
    func completeOnboarding(_ result: OnboardingResult) {
        apply(result)
        services.planStore.save(result.plan)
        do {
            try onboardingStorage.save(result)
            onboardingSaveFailed = false
        } catch {
            onboardingSaveFailed = true
        }
        onboardingCompleted = true
    }

    private func apply(_ result: OnboardingResult) {
        profile = result.profile
        plan = services.planStore.templatePlan ?? result.plan
        healthHistory = result.health
        healthAccess = result.healthAccess
    }

    var today: RecoverySnapshot? { recovery.first }

    // MARK: Profile and data

    /// Deletes the health history from the phone. The profile keeps working without the derived exclusions; the
    /// plan stays as it is until the user rebuilds it.
    func deleteHealthHistory() {
        healthHistory = HealthHistory()
        profile.avoidTags = []
        profile.easyStart = false
        try? onboardingStorage.save(OnboardingResult(profile: profile, health: healthHistory, plan: plan,
                                                     healthAccess: healthAccess ?? .sampleData))
        try? onboardingStorage.deleteHealthHistory()
    }

    /// Builds the plan again for the current profile (backend first, local fallback). Returns false on failure.
    @MainActor
    func rebuildPlan() async -> Bool {
        guard let new = try? await services.planGenerator.generatePlan(for: profile) else { return false }
        plan = new
        services.planStore.save(new)
        restoredSessionIds = []
        try? onboardingStorage.save(OnboardingResult(profile: profile, health: healthHistory, plan: plan,
                                                     healthAccess: healthAccess ?? .sampleData))
        await refreshRecommendation()
        return true
    }

    // MARK: Plan changes accepted from the coach

    /// Makes a change the coach proposed and the user accepted. The plan is checked again first: it may have changed
    /// since the proposal was made. Today and Plan update on their own, they read `plan`.
    @MainActor
    func applyPlanChange(_ proposal: PlanChangeProposal) -> Result<PlanChangeProposal, PlanChangeError> {
        // A finished session is final.
        guard !services.planStore.completedSessionIds().contains(proposal.sessionId) else { return .failure(.sessionDone) }
        let changer = PlanChanger(catalog: catalog, profile: profile)
        do {
            let result = try changer.apply(proposal, to: plan)
            plan = result.plan
            persistPlan()
            return .success(result.proposal)
        } catch let error as PlanChangeError {
            return .failure(error)
        } catch {
            return .failure(.planChanged)
        }
    }

    /// Puts the session back as it was before the accepted change (only if nothing else touched it since).
    @MainActor
    func undoPlanChange(_ proposal: PlanChangeProposal) -> Result<PlanChangeProposal, PlanChangeError> {
        let changer = PlanChanger(catalog: catalog, profile: profile)
        do {
            let result = try changer.undo(proposal, in: plan)
            plan = result.plan
            persistPlan()
            return .success(result.proposal)
        } catch let error as PlanChangeError {
            return .failure(error)
        } catch {
            return .failure(.planChanged)
        }
    }

    // MARK: Plan edited by the user

    /// The last manual edit, so the Plan screen can offer "Cofnij". Cleared by the next edit and by dismissing.
    struct PlanEditUndo: Equatable {
        var summary: String
        var previous: TrainingPlan
    }
    private(set) var lastEdit: PlanEditUndo?

    private var editor: PlanEditor { PlanEditor(catalog: catalog, profile: profile) }

    /// Exercises the person can put in a session: from the catalog, fitting equipment, level and avoided movements.
    func exerciseCandidates(excluding ids: Set<String>, timed: Bool? = nil) -> [ExerciseItem] {
        editor.candidates(excluding: ids, timed: timed)
    }

    /// One change of a session made by hand. Finished sessions are final, so the editor sees the plan with `done`.
    @MainActor
    @discardableResult
    func edit(_ edit: PlanEdit, sessionId: UUID, scope: PlanEditScope = .thisSession) -> Result<String, PlanChangeError> {
        do {
            let result = try editor.apply(edit, to: sessionId, scope: scope, in: resolvedPlan)
            commit(result)
            return .success(result.summary)
        } catch let error as PlanChangeError {
            return .failure(error)
        } catch {
            return .failure(.notApplied)
        }
    }

    /// A session of your own on a free day.
    @MainActor
    @discardableResult
    func addSession(on day: Date, title: String, exerciseIds: [String]) -> Result<String, PlanChangeError> {
        do {
            let result = try editor.addSession(on: day, title: title, exerciseIds: exerciseIds, in: resolvedPlan)
            commit(result)
            return .success(result.summary)
        } catch let error as PlanChangeError {
            return .failure(error)
        } catch {
            return .failure(.notApplied)
        }
    }

    private func commit(_ result: PlanEditResult) {
        lastEdit = PlanEditUndo(summary: result.summary, previous: plan)
        services.planStore.save(result.plan)
        plan = services.planStore.templatePlan ?? result.plan  // the saved plan never carries `done`
        persistPlan()
    }

    /// Puts the plan back as it was before the last edit.
    @MainActor
    func undoLastEdit() {
        guard let last = lastEdit else { return }
        plan = last.previous
        lastEdit = nil
        services.planStore.save(plan)
        persistPlan()
    }

    func dismissLastEdit() { lastEdit = nil }

    /// Saves the plan with the profile. Before onboarding is done nothing is written: a saved profile would make the
    /// next launch skip onboarding.
    private func persistPlan() {
        guard onboardingCompleted else { return }
        services.planStore.save(plan)
        try? onboardingStorage.save(OnboardingResult(profile: profile, health: healthHistory, plan: plan,
                                                     healthAccess: healthAccess ?? .sampleData))
    }

    /// Removes everything the app stored on this phone and starts onboarding again.
    @MainActor
    func deleteAllData() async {
        try? onboardingStorage.clear()
        services.planStore.clear()
        _ = try? await services.checkInStore.removeAll()
        services.localHistory.removeAll()
        services.consent.reset()
        await services.coachHistory.clear()
        await (services.recommendationText as? RecommendationTexter)?.clearCache()
        profile = SampleData.profile
        plan = SampleData.plan
        healthHistory = HealthHistory()
        healthAccess = nil
        checkIn = nil
        lastTechnique = SampleData.technique
        restoredSessionIds = []
        onboardingCompleted = false
        await refreshRecommendation()
    }

    // MARK: Session adjustment

    /// Sessions for which the user chose the original plan over today's lighter version.
    private(set) var restoredSessionIds: Set<UUID> = []

    /// The session the rule engine's decision applies to: today's, or the next one when today is free (the one the
    /// Today screen shows). Other sessions stay as planned.
    func adjustment(for session: PlannedSession) -> PlanAdjustment {
        guard session.id == todaySession?.session.id, session.status != .skipped, !restoredSessionIds.contains(session.id),
              !services.planStore.completedSessionIds().contains(session.id) else {
            return PlanAdjustment(original: session, session: session, changes: [], isRestDay: false)
        }
        return PlanAdjuster(catalog: catalog).adjust(session, for: recommendation, technique: lastTechnique,
                                                     equipment: profile.equipment)
    }

    func isRestored(_ session: PlannedSession) -> Bool { restoredSessionIds.contains(session.id) }

    /// "Przywróć oryginał" and back.
    func toggleOriginal(_ session: PlannedSession) {
        if restoredSessionIds.contains(session.id) { restoredSessionIds.remove(session.id) }
        else { restoredSessionIds.insert(session.id) }
    }

    // MARK: Recommendation and results

    /// Today's saved check-in (nil when there is none yet).
    @MainActor
    func loadSavedCheckIn() async {
        checkIn = await services.checkIns.checkIns(days: 1).first
    }

    /// Recomputes today's recommendation with the rule engine from the current inputs.
    @MainActor
    func refreshRecommendation() async {
        let new = await services.recommendation.todayRecommendation()
        if new != recommendation { recommendation = new }  // sets the local text immediately
        // The model's wording comes later and must never block the card (nor outlive a newer recommendation).
        textTask?.cancel()
        let texter = services.recommendationText
        textTask = Task { @MainActor [weak self] in
            let text = await texter.text(for: new)
            guard !Task.isCancelled, let self, self.recommendation == new else { return }
            self.recommendationText = text
        }
    }

    @MainActor
    func contentDidUpdate() async {
        contentRevision += 1
        await refreshRecommendation()
    }

    @MainActor
    func saveCheckIn(_ new: CheckIn) {
        checkIn = new
        Task {
            _ = try? await services.checkInStore.save(new)
            await refreshRecommendation()
        }
    }

    /// A finished live set: stored on the phone, feeds the rule engine.
    @MainActor
    func recordSet(_ summary: SetSummary) {
        if let result = services.localHistory.record(summary) { lastTechnique = result }
        Task { await refreshRecommendation() }
    }

    func exercise(id: String) -> ExerciseItem? {
        catalog.first { $0.id == id }
    }

    /// The plan with `done` on the finished sessions (the saved plan itself never carries it).
    var resolvedPlan: TrainingPlan { services.planStore.resolved(plan) }

    /// Today's session, or the next planned one. Nil when the plan has run out.
    var todaySession: (session: PlannedSession, isToday: Bool)? {
        guard let match = plan.sessionOnOrAfter(Date()) else { return nil }
        return (match, plan.session(on: Date())?.id == match.id)
    }

    /// True when every session of the plan is in the past: time to build the next one.
    var planHasEnded: Bool { plan.hasEnded(on: Date()) }
}

enum AppTab: Hashable {
    case today, plan, analysis, coach, progress
}

@Observable
final class AppRouter {
    var tab: AppTab = .today
}
