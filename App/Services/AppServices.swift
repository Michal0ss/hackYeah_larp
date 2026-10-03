import Contracts

/// The one place where real implementations replace the sample ones.
/// Each owner changes only HIS line when his service is ready (small, conflict-free diffs):
///   catalog, plan, planGenerator        Maciek
///   recovery, checkIns, recommendation,
///   healthAuthorization                 Wiktor
///   technique                           Michał
struct AppServices {
    var catalog: ExerciseCatalogProviding = SampleServices()
    var plan: PlanProviding = SampleServices()
    var recovery: RecoveryProviding = SampleServices()
    var checkIns: CheckInProviding = SampleServices()
    var technique: TechniqueHistoryProviding = SampleServices()
    var recommendation: RecommendationProviding = SampleServices()
    var healthAuthorization: HealthAuthorizing = SampleServices()
    var planGenerator: PlanGenerating = SampleServices()
}
