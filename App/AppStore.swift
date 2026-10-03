import SwiftUI
import Observation
import Contracts

/// In-memory app state. It starts on sample data (marked as simulated in the UI).
/// Owners replace the pieces with real sources: Wiktor (recovery, check-in, recommendation),
/// Maciek (profile, plan), Bartek (technique results).
@Observable
final class AppStore {
    var profile: UserProfile = SampleData.profile
    var plan: TrainingPlan = SampleData.plan
    var catalog: [ExerciseItem] = SampleData.catalog
    var recovery: [RecoverySnapshot] = SampleData.recovery
    var checkIn: CheckIn? = SampleData.checkIn
    var lastTechnique: TechniqueResult? = SampleData.technique
    var recommendation: DailyRecommendation = SampleData.recommendation

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
