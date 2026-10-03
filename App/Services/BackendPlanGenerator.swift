import API
import Contracts
import Foundation

/// Plan from the backend (model → validation → template there). When the backend cannot be reached, the local
/// fallback builds a plan, so onboarding never gets stuck. Maciek's `feat/maciek-plan-generator` replaces this
/// with the full version (local templates from content/plan_templates.json, warnings in the UI).
struct BackendPlanGenerator: PlanGenerating {
    let api: FormaAPI
    let fallback: PlanGenerating

    func generatePlan(for profile: UserProfile) async throws -> TrainingPlan {
        do {
            return try await api.generatePlan(for: profile).plan
        } catch {
            return try await fallback.generatePlan(for: profile)
        }
    }
}
