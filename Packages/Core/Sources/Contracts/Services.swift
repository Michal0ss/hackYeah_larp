import Foundation

// Service interfaces between modules. Each owner implements the ones in his area and codes against the
// others through these protocols, using `SampleServices` until the real implementation lands.
// This is what lets everyone work in parallel on their own branch.
//
// Who implements what:
//   ExerciseCatalogProviding, PlanProviding,
//   PlanGenerating                                     Maciek  (Content, Plan)
//   RecoveryProviding, CheckInProviding,
//   RecommendationProviding, HealthAuthorizing         Wiktor  (Health, Insights)
//   TechniqueHistoryProviding                          Michał  (app store; Bartek supplies the results)
//   SessionFeedbackStoring                             Michał  (feedback after a workout; Wiktor's rules and Maciek's tools read it)
//   SetFeedbackProviding                               Wiktor  (text after a set / workout; Michał shows it)

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

public protocol SessionFeedbackStoring: Sendable {
    func save(_ feedback: SessionFeedback) async
    /// Newest first.
    func feedbacks(limit: Int) async -> [SessionFeedback]
}

public protocol SetFeedbackProviding: Sendable {
    /// Two or three sentences after a set. Never throws: without the model (no consent, no network) it returns a
    /// template built from the findings, with `isFromModel == false`.
    func feedback(for set: SetSummary) async -> FeedbackText
    /// A short wrap-up after the workout, from what the user reported and the sets of that session.
    func feedback(for session: SessionFeedback, sets: [SetSummary]) async -> FeedbackText
}

public protocol RecommendationProviding: Sendable {
    func todayRecommendation() async -> DailyRecommendation
}

public protocol HealthAuthorizing: Sendable {
    /// Asks the user for read access to sleep, resting heart rate and HRV (Apple Health).
    /// Returns false when the user declined or HealthKit is not available.
    func requestAccess() async -> Bool
}

public protocol PlanGenerating: Sendable {
    /// Builds the weekly plan for a profile. Must use only catalog exercises, honor `equipment`, `daysPerWeek`,
    /// `avoidTags` and `easyStart`, and set `source`. Falls back to a template plan on model errors,
    /// so it throws only for hard failures.
    func generatePlan(for profile: UserProfile) async throws -> TrainingPlan
}

/// Simulated implementations of every service, backed by `SampleData`.
public struct SampleServices: ExerciseCatalogProviding, PlanProviding, RecoveryProviding, CheckInProviding,
                              TechniqueHistoryProviding, RecommendationProviding, HealthAuthorizing, PlanGenerating,
                              SessionFeedbackStoring, SetFeedbackProviding {
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

    public func requestAccess() async -> Bool { true }

    public func generatePlan(for profile: UserProfile) async throws -> TrainingPlan {
        SamplePlanBuilder.plan(for: profile)
    }

    /// Sample storage does not keep anything: `save` is a no-op and the list is always the sample feedback.
    public func save(_ feedback: SessionFeedback) async {}

    public func feedbacks(limit: Int) async -> [SessionFeedback] { Array([SampleData.sessionFeedback].prefix(limit)) }

    public func feedback(for set: SetSummary) async -> FeedbackText {
        var text = "Seria \(set.setIndex) zakończona."
        if let score = set.techniqueScore { text += " Technika \(score)/100," } else { text += " Technika bez oceny," }
        text += " tempo \(set.tempoScore)/100."
        if let finding = (set.techniqueFindings + set.tempoFindings).first(where: { $0.severity != .good }) {
            text += " Do poprawy: \(finding.title.lowercased())."
        }
        return FeedbackText(text: text, isFromModel: false, isSimulated: true)
    }

    public func feedback(for session: SessionFeedback, sets: [SetSummary]) async -> FeedbackText {
        FeedbackText(text: "Trening zakończony: \(session.completedSets) z \(session.plannedSets) serii, wysiłek \(session.perceivedExertion)/10.",
                     isFromModel: false, isSimulated: true)
    }
}
