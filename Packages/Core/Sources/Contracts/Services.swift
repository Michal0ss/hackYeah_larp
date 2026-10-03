import Foundation

// Service interfaces between modules. Each owner implements the ones in his area and codes against the
// others through these protocols, using `SampleServices` until the real implementation lands.
// This is what lets everyone work in parallel on their own branch.
//
// Who implements what:
//   ExerciseCatalogProviding, PlanProviding            Maciek  (Content, Plan)
//   RecoveryProviding, CheckInProviding,
//   RecommendationProviding                            Wiktor  (Health, Insights)
//   TechniqueHistoryProviding                          Michał  (app store; Bartek supplies the results)

public protocol ExerciseCatalogProviding: Sendable {
    var exercises: [ExerciseItem] { get }
}

public extension ExerciseCatalogProviding {
    func exercise(id: String) -> ExerciseItem? {
        exercises.first { $0.id == id }
    }
}

public protocol PlanProviding: Sendable {
    func currentPlan() async -> TrainingPlan?
    /// Today's session, or the next planned one.
    func todaySession() async -> PlannedSession?
}

public protocol RecoveryProviding: Sendable {
    /// Daily summaries, newest first. Never raw HealthKit samples.
    func snapshots(days: Int) async -> [RecoverySnapshot]
}

public protocol CheckInProviding: Sendable {
    /// Newest first.
    func checkIns(days: Int) async -> [CheckIn]
}

public protocol TechniqueHistoryProviding: Sendable {
    /// Newest first.
    func results(limit: Int) async -> [TechniqueResult]
    func setSummaries(limit: Int) async -> [SetSummary]
}

public protocol RecommendationProviding: Sendable {
    func todayRecommendation() async -> DailyRecommendation
}

/// Simulated implementations of every service, backed by `SampleData`.
public struct SampleServices: ExerciseCatalogProviding, PlanProviding, RecoveryProviding, CheckInProviding,
                              TechniqueHistoryProviding, RecommendationProviding {
    public init() {}

    public var exercises: [ExerciseItem] { SampleData.catalog }

    public func currentPlan() async -> TrainingPlan? { SampleData.plan }

    public func todaySession() async -> PlannedSession? {
        let weekday = Calendar(identifier: .iso8601).component(.weekday, from: Date())
        let planWeekday = weekday == 1 ? 7 : weekday - 1
        let sessions = SampleData.plan.sessions.sorted { $0.weekday < $1.weekday }
        return sessions.first { $0.weekday == planWeekday }
            ?? sessions.first { $0.weekday > planWeekday }
            ?? sessions.first
    }

    public func snapshots(days: Int) async -> [RecoverySnapshot] { Array(SampleData.recovery.prefix(days)) }

    public func checkIns(days: Int) async -> [CheckIn] { [SampleData.checkIn] }

    public func results(limit: Int) async -> [TechniqueResult] { [SampleData.technique] }

    public func setSummaries(limit: Int) async -> [SetSummary] { [] }

    public func todayRecommendation() async -> DailyRecommendation { SampleData.recommendation }
}
