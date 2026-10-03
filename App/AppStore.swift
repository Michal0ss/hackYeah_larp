import SwiftUI
import Observation
import Contracts
import Insights
import Onboarding

/// In-memory app state. It starts on sample data (marked as simulated in the UI).
/// Owners replace the pieces with real sources: Wiktor (recovery, check-in, recommendation),
/// Maciek (profile, plan), Bartek (technique results).
@Observable
final class AppStore {
    /// Service implementations. Sample ones until the owners plug in the real ones (App/Services/AppServices.swift).
    var services = AppServices()

    var profile: UserProfile = SampleData.profile
    var plan: TrainingPlan = SampleData.plan
    /// Bumped when newer content arrives from the backend, so screens that read `catalog` refresh.
    private(set) var contentRevision = 0
    var catalog: [ExerciseItem] { _ = contentRevision; return services.catalog.exercises }
    var recovery: [RecoverySnapshot] = SampleData.recovery
    var checkIn: CheckIn? = SampleData.checkIn
    var lastTechnique: TechniqueResult? = SampleData.technique
    var recommendation: DailyRecommendation = SampleData.recommendation

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
        if arguments.contains("-reset-onboarding") { try? onboardingStorage.clear() }
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
        plan = result.plan
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
        restoredSessionIds = []
        try? onboardingStorage.save(OnboardingResult(profile: profile, health: healthHistory, plan: plan,
                                                     healthAccess: healthAccess ?? .sampleData))
        await refreshRecommendation()
        return true
    }

    /// Removes everything the app stored on this phone and starts onboarding again.
    @MainActor
    func deleteAllData() async {
        try? onboardingStorage.clear()
        _ = try? await services.checkInStore.removeAll()
        services.localHistory.removeAll()
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

    var todayPlanWeekday: Int {
        let weekday = Calendar(identifier: .iso8601).component(.weekday, from: Date())
        return weekday == 1 ? 7 : weekday - 1
    }

    /// The session the rule engine's decision applies to: today's, or the next one when today is free (the one the
    /// Today screen shows). Other sessions stay as planned.
    func adjustment(for session: PlannedSession) -> PlanAdjustment {
        guard session.id == todaySession?.session.id, !restoredSessionIds.contains(session.id) else {
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
        recommendation = await services.recommendation.todayRecommendation()
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

    /// Today's session, or the next planned one.
    var todaySession: (session: PlannedSession, isToday: Bool)? {
        let weekday = Calendar(identifier: .iso8601).component(.weekday, from: Date())
        // Calendar weekday: 1 = Sunday. Plan weekday: 1 = Monday.
        let planWeekday = weekday == 1 ? 7 : weekday - 1
        if let match = plan.sessions.first(where: { $0.weekday == planWeekday }) {
            return (match, true)
        }
        let upcoming = plan.sessions.sorted { $0.weekday < $1.weekday }
        if let next = upcoming.first(where: { $0.weekday > planWeekday }) ?? upcoming.first {
            return (next, false)
        }
        return nil
    }
}

enum AppTab: Hashable {
    case today, plan, analysis, coach, progress
}

@Observable
final class AppRouter {
    var tab: AppTab = .today
}
