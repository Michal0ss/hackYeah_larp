import Contracts
import Foundation

// The coach reads the same data the screens show. Plan, recommendation and profile live in `AppStore` (on the main
// actor); these adapters expose them through the service protocols the coach tools are written against.

/// The current plan as the user sees it: today's session already adjusted by the rule engine's decision.
///
/// `adjusted` says whether to show that adjustment. The coach turns it off while the user has not agreed to health
/// data going to the model: the adjustment is derived from sleep, HRV and the check-in, so it must not leak through
/// the plan either.
struct StorePlanProvider: PlanProviding, @unchecked Sendable {
    let store: AppStore
    var adjusted: @Sendable () -> Bool = { true }

    func currentPlan() async -> TrainingPlan? {
        let adjusted = adjusted()
        return await MainActor.run {
            var plan = store.plan
            if adjusted { plan.sessions = plan.sessions.map { store.adjustment(for: $0).session } }
            return plan
        }
    }

    func todaySession() async -> PlannedSession? {
        let adjusted = adjusted()
        return await MainActor.run {
            store.todaySession.map { adjusted ? store.adjustment(for: $0.session).session : $0.session }
        }
    }
}

/// Today's recommendation exactly as the Today screen shows it.
struct StoreRecommendationProvider: RecommendationProviding, @unchecked Sendable {
    let store: AppStore

    func todayRecommendation() async -> DailyRecommendation {
        await MainActor.run { store.recommendation }
    }
}
