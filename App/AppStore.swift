import SwiftUI
import Observation
import Contracts
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
    var catalog: [ExerciseItem] = SampleData.catalog
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
