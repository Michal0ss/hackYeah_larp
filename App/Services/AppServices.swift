import API
import Content
import Contracts
import Health
import Insights

/// The one place where real implementations replace the sample ones.
/// Each owner changes only HIS line when his service is ready (small, conflict-free diffs):
///   catalog, plan, planGenerator        Maciek
///   recovery, checkIns, recommendation,
///   healthAuthorization                 Wiktor
///   technique                           Michał
struct AppServices {
    /// Backend client (adres i token z Config/*.xcconfig). Maciek and Wiktor use it in their services.
    var api = FormaAPI()
    // Bundled content/ copy, refreshed from the backend (Michał, feat/michal-content-sync).
    var catalog: ExerciseCatalogProviding = ContentRepository.shared
    var plan: PlanProviding = SampleServices()
    /// Apple Health summaries with sample fallback (marked as simulated), one service for data and permission.
    let healthKit = HealthKitService()
    var recovery: RecoveryProviding
    /// In memory until Wiktor's check-in store lands. The app writes through `localCheckIns`.
    let localCheckIns = InMemoryCheckIns()
    var checkIns: CheckInProviding
    /// Results of live sets and analyses (Michał). The app and Bartek write through `localHistory`.
    let localHistory = LocalTechniqueHistory.shared
    var technique: TechniqueHistoryProviding
    // Rule engine (Wiktor) over recovery (sample), the check-ins and the recorded results.
    var recommendation: RecommendationProviding
    var healthAuthorization: HealthAuthorizing
    /// Backend first, local fallback until Maciek's PlanGenerator replaces it.
    var planGenerator: PlanGenerating

    init() {
        recovery = healthKit
        healthAuthorization = healthKit
        checkIns = localCheckIns
        technique = localHistory
        recommendation = InsightRecommendationService(recovery: healthKit, checkIns: localCheckIns,
                                                      technique: localHistory, catalog: ContentRepository.shared)
        planGenerator = BackendPlanGenerator(api: api, fallback: SampleServices())
    }
}
