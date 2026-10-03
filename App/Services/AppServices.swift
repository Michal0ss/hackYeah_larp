import API
import Coaching
import Content
import Contracts
import Health
import Insights
import Plan

/// The one place where real implementations replace the sample ones.
/// Each owner changes only HIS line when his service is ready (small, conflict-free diffs):
///   catalog, plan, planGenerator        Maciek
///   recovery, checkIns, recommendation,
///   healthAuthorization                 Wiktor
///   technique, sessionFeedback          Michał
///   setFeedback                         Wiktor
struct AppServices {
    /// Backend client (adres i token z Config/*.xcconfig). Maciek and Wiktor use it in their services.
    var api = FormaAPI()
    // Bundled content/ copy, refreshed from the backend (Michał, feat/michal-content-sync).
    var catalog: ExerciseCatalogProviding = ContentRepository.shared
    var plan: PlanProviding = SampleServices()
    /// The user's consent to pass health summaries to the model, and the conversation with the coach (Maciek).
    let consent = ConsentStore.standard
    let coachHistory = CoachHistoryStore.standard
    /// Apple Health summaries with sample fallback (marked as simulated), one service for data and permission.
    let healthKit = HealthKitService()
    var recovery: RecoveryProviding
    /// Check-ins kept on the phone (Wiktor's CheckInStore). The app saves through `checkInStore`.
    let checkInStore = CheckInStore.standard
    var checkIns: CheckInProviding
    /// Results of live sets and analyses (Michał). The app and Bartek write through `localHistory`.
    let localHistory = LocalTechniqueHistory.shared
    var technique: TechniqueHistoryProviding
    /// Feedback after a workout (RPE, pain, a note). Sample until Michał's local store lands (feat/michal-session-feedback).
    var sessionFeedback: SessionFeedbackStoring = SampleServices()
    /// Coach text after a set and after a workout. Sample until Wiktor's SetFeedbackTexter lands.
    var setFeedback: SetFeedbackProviding = SampleServices()
    // Rule engine (Wiktor) over recovery (Apple Health or sample), the check-ins and the recorded results.
    var recommendation: RecommendationProviding
    /// Wording of the daily recommendation: the model via the backend when allowed, the phone's own text otherwise.
    /// Health summaries go to the model only after the user agreed (`consent`, asked on the coach screen).
    var recommendationText: RecommendationTexting
    var healthAuthorization: HealthAuthorizing
    /// Backend first, then the bundled template on the phone (Maciek's PlanGenerator); the plan carries a notice saying why.
    var planGenerator: PlanGenerating

    init() {
        recovery = healthKit
        healthAuthorization = healthKit
        checkIns = checkInStore
        technique = localHistory
        recommendation = InsightRecommendationService(recovery: healthKit, checkIns: checkInStore,
                                                      technique: localHistory, catalog: ContentRepository.shared)
        recommendationText = RecommendationTexter(fetcher: BackendRecommendationFetcher(api: api), hasConsent: { [consent] in consent.isGranted })
        planGenerator = PlanGenerator(backend: api, catalog: ContentRepository.shared)
    }
}
