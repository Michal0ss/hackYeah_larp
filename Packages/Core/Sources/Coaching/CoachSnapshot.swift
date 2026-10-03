import API
import Contracts
import Foundation

/// Builds what the coach knows about the user's training before the first question (`TrainingSnapshot`).
public protocol CoachSnapshotProviding: Sendable {
    func snapshot(healthConsent: Bool) async -> TrainingSnapshot
}

/// Reads the same plan and technique results the screens show (through the service protocols, so it works on sample
/// data and on the real services).
///
/// The consent rule is applied here as well as on the server: without consent a session that was lightened for today
/// is described as planned and its reason is left out, because that reason comes from sleep, HRV and the check-in.
public struct CoachSnapshotBuilder: CoachSnapshotProviding {
    private let plan: PlanProviding
    private let technique: TechniqueHistoryProviding
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(plan: PlanProviding, technique: TechniqueHistoryProviding, calendar: Calendar = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.plan = plan
        self.technique = technique
        self.calendar = calendar
        self.now = now
    }

    public func snapshot(healthConsent: Bool) async -> TrainingSnapshot {
        let weekday = isoWeekday(now())
        let currentPlan = await plan.currentPlan()
        let next = await plan.todaySession()
        let latest = await technique.results(limit: 1).first
        return TrainingSnapshot(
            today: weekday,
            planSource: currentPlan?.source,
            nextSession: next.map { digest($0, healthConsent: healthConsent) },
            nextSessionIsToday: next.map { isToday($0) } ?? false,
            // The seven days from today: each weekday once, whatever the length of the plan.
            week: (currentPlan?.window(from: now(), calendar: calendar) ?? [])
                .map { digest($0, healthConsent: healthConsent) },
            lastTechnique: latest.map(techniqueDigest)
        )
    }

    private func digest(_ session: PlannedSession, healthConsent: Bool) -> SessionDigest {
        SessionDigest(weekday: session.weekday, title: session.title,
                      status: healthConsent || session.status != .adapted ? session.status : .planned,
                      adaptationNote: healthConsent ? session.adaptationNote : nil,
                      exercises: session.exercises.map(ExerciseDigest.init))
    }

    private func techniqueDigest(_ result: TechniqueResult) -> TechniqueDigest {
        let rank: [FindingSeverity: Int] = [.major: 0, .minor: 1, .good: 2]
        let findings = result.findings.sorted { (rank[$0.severity] ?? 3) < (rank[$1.severity] ?? 3) }
            .prefix(TechniqueDigest.maxFindings).map(FindingDigest.init)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: result.date),
                                           to: calendar.startOfDay(for: now())).day ?? 0
        return TechniqueDigest(exerciseId: result.exerciseId, daysAgo: max(0, days), score: result.score,
                               findings: Array(findings), substituteExerciseId: result.substituteExerciseId,
                               isSimulated: result.isSimulated)
    }

    private func isToday(_ session: PlannedSession) -> Bool {
        if let date = session.date { return calendar.isDate(date, inSameDayAs: now()) }
        return session.weekday == isoWeekday(now())
    }

    private func isoWeekday(_ date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 ? 7 : weekday - 1
    }
}
