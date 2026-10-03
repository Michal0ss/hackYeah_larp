import API
import Coaching
import Content
import Contracts
import Health
import Insights
import Onboarding
import Plan
import LiveSet

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
    /// Feedback after a workout (RPE, pain, a note), kept on the phone (Michał). The coach tool reads it after consent.
    let sessionFeedbackStore = SessionFeedbackStore(fileURL: SessionFeedbackStore.defaultFileURL())
    var sessionFeedback: SessionFeedbackStoring
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
    /// The weekly plan and the sessions finished in each week, kept on the phone (Maciek's PlanStore). `plan` reads it.
    let planStore: PlanStore
    /// The sets the user did in a workout, with the weight where they typed one (Maciek's TrainingLogStore).
    let trainingLog = TrainingLogStore(fileURL: TrainingLogStore.defaultFileURL())

    init() {
        sessionFeedback = sessionFeedbackStore
        recovery = healthKit
        healthAuthorization = healthKit
        checkIns = checkInStore
        technique = localHistory
        recommendation = InsightRecommendationService(recovery: healthKit, checkIns: checkInStore,
                                                      technique: localHistory, catalog: ContentRepository.shared)
        recommendationText = RecommendationTexter(fetcher: BackendRecommendationFetcher(api: api), hasConsent: { [consent] in consent.isGranted })
        planGenerator = PlanGenerator(backend: api, catalog: ContentRepository.shared)
        // The first launch after the update starts from the plan saved by onboarding.
        planStore = PlanStore(fileURL: PlanStore.defaultFileURL(), bootstrap: { FileOnboardingStorage.default.load()?.plan })
        plan = planStore
    }
}
