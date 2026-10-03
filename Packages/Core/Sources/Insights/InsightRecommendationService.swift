import Foundation
import Contracts

/// `RecommendationProviding` backed by the rule engine. Reads recovery, check-ins and technique results
/// through the shared protocols, so it works the same on `SampleServices` and on the real services.
public struct InsightRecommendationService: RecommendationProviding {
    private let recovery: RecoveryProviding
    private let checkIns: CheckInProviding
    private let technique: TechniqueHistoryProviding
    private let catalog: ExerciseCatalogProviding
    private let engine: InsightEngine
    private let now: @Sendable () -> Date

    public init(recovery: RecoveryProviding, checkIns: CheckInProviding, technique: TechniqueHistoryProviding,
                catalog: ExerciseCatalogProviding, engine: InsightEngine = InsightEngine(),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.recovery = recovery
        self.checkIns = checkIns
        self.technique = technique
        self.catalog = catalog
        self.engine = engine
        self.now = now
    }

    public func todayRecommendation() async -> DailyRecommendation {
        let window = max(engine.thresholds.care.windowDays, engine.thresholds.care.persistentDays) + 1
        async let snapshots = recovery.snapshots(days: window)
        async let notes = checkIns.checkIns(days: window)
        async let results = technique.results(limit: 30)
        let input = InsightInput(snapshots: await snapshots, checkIns: await notes, techniqueResults: await results,
                                 catalog: catalog.exercises, now: now())
        return engine.recommend(input)
    }
}
