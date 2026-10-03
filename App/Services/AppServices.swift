import API
import Content
import Contracts
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
    var recovery: RecoveryProviding = SampleServices()
    var checkIns: CheckInProviding = SampleServices()
    var technique: TechniqueHistoryProviding = SampleServices()
    // Rule engine over the sample inputs until the real recovery and check-in stores are plugged in (Wiktor).
    var recommendation: RecommendationProviding = InsightRecommendationService(
        recovery: SampleServices(), checkIns: SampleServices(), technique: SampleServices(), catalog: SampleServices())
    var healthAuthorization: HealthAuthorizing = SampleServices()
    var planGenerator: PlanGenerating = SampleServices()
}
