import Contracts
import Foundation

// The coach reads the same data the screens show. Plan, recommendation and profile live in `AppStore` (on the main
// actor); these adapters expose them through the service protocols the coach tools are written against.

/// The current plan as the user sees it: today's session already adjusted by the rule engine's decision.
struct StorePlanProvider: PlanProviding, @unchecked Sendable {
    let store: AppStore

    func currentPlan() async -> TrainingPlan? {
        await MainActor.run {
            var plan = store.plan
            plan.sessions = plan.sessions.map { store.adjustment(for: $0).session }
            return plan
        }
    }

    func todaySession() async -> PlannedSession? {
        await MainActor.run { store.todaySession.map { store.adjustment(for: $0.session).session } }
    }
}

/// Today's recommendation exactly as the Today screen shows it.
struct StoreRecommendationProvider: RecommendationProviding, @unchecked Sendable {
    let store: AppStore

    func todayRecommendation() async -> DailyRecommendation {
        await MainActor.run { store.recommendation }
    }
}
