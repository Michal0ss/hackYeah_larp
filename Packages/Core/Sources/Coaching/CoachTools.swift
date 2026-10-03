import API
import Contracts
import Foundation

/// What a tool hands back to the model, plus what the app needs to show about it.
public struct CoachToolOutput: Equatable, Sendable {
    /// JSON text. A summary only: never raw HealthKit samples, never free text the user wrote (check-in notes).
    public var content: String
    public var isError: Bool
    /// Short Polish name of the data used, shown under the answer ("sen z 7 dni").
    public var sourceLabel: String?
    /// True when the data is sample data; the answer is then marked "Dane przykładowe".
    public var isSimulated: Bool

    public init(content: String, isError: Bool = false, sourceLabel: String? = nil, isSimulated: Bool = false) {
        self.content = content
        self.isError = isError
        self.sourceLabel = sourceLabel
        self.isSimulated = isSimulated
    }
}

public protocol CoachToolRunning: Sendable {
    func run(name: String, input: JSONValue) async -> CoachToolOutput
}

/// Tool names the backend offers the model (backend/app/ai/tools.py). The model asks, the phone answers from local data.
public enum CoachToolName {
    public static let currentPlan = "get_current_plan"
    public static let techniqueHistory = "get_technique_history"
    public static let todayRecommendation = "get_today_recommendation"
    public static let recoverySummary = "get_recovery_summary"
    public static let checkIns = "get_checkins"
    public static let sessionFeedback = "get_session_feedback"

    /// Tools that read health data: they answer only with the user's consent.
    public static let health: Set<String> = [todayRecommendation, recoverySummary, checkIns, sessionFeedback]
}

/// Runs the coach tools against the shared service protocols, so they work on sample data and on the real services.
///
/// The consent rule is applied here as well as on the server: a health tool without consent returns an error and
/// does not even read the data.
public struct CoachTools: CoachToolRunning {
    private let plan: PlanProviding
    private let catalog: ExerciseCatalogProviding
    private let recovery: RecoveryProviding
    private let checkIns: CheckInProviding
    private let technique: TechniqueHistoryProviding
    private let recommendation: RecommendationProviding
    private let feedback: SessionFeedbackStoring?
    private let hasHealthConsent: @Sendable () -> Bool
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    public init(plan: PlanProviding, catalog: ExerciseCatalogProviding, recovery: RecoveryProviding,
                checkIns: CheckInProviding, technique: TechniqueHistoryProviding,
                recommendation: RecommendationProviding, feedback: SessionFeedbackStoring? = nil,
                hasHealthConsent: @escaping @Sendable () -> Bool,
                calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.plan = plan
        self.catalog = catalog
        self.recovery = recovery
        self.checkIns = checkIns
        self.technique = technique
        self.recommendation = recommendation
        self.feedback = feedback
        self.hasHealthConsent = hasHealthConsent
        self.calendar = calendar
        self.now = now
    }

    public func run(name: String, input: JSONValue) async -> CoachToolOutput {
        if CoachToolName.health.contains(name), !hasHealthConsent() {
            return CoachToolOutput(content: Self.json(["error": .string("Użytkownik nie wyraził zgody na dane zdrowotne.")]),
                                   isError: true)
        }
        switch name {
        case CoachToolName.currentPlan: return await currentPlan(healthConsent: hasHealthConsent())
        case CoachToolName.techniqueHistory: return await techniqueHistory(input)
        case CoachToolName.todayRecommendation: return await todayRecommendation()
        case CoachToolName.recoverySummary: return await recoverySummary(days: Self.days(input, default: 7))
        case CoachToolName.checkIns: return await recentCheckIns(days: Self.days(input, default: 7))
        case CoachToolName.sessionFeedback: return await recentSessionFeedback(limit: Self.clamp(input["limit"]?.intValue ?? 3, 1, 10))
        default:
            return CoachToolOutput(content: Self.json(["error": .string("Nieznane narzędzie.")]), isError: true)
        }
    }

    // MARK: plan

    private static let weekdayNames = ["poniedziałek", "wtorek", "środa", "czwartek", "piątek", "sobota", "niedziela"]

    private func name(of exerciseId: String) -> String {
        catalog.exercise(id: exerciseId)?.name ?? exerciseId
    }

    /// The reason a session was lightened comes from health signals (sleep, HRV, the check-in), so it is told only
    /// with consent; without it a lightened session reads as planned.
    private func currentPlan(healthConsent: Bool) async -> CoachToolOutput {
        guard let plan = await plan.currentPlan() else {
            return CoachToolOutput(content: Self.json(["plan": .null, "note": .string("Użytkownik nie ma jeszcze planu.")]),
                                   sourceLabel: "plan treningowy")
        }
        let isoWeekday = calendar.component(.weekday, from: now())
        let today = isoWeekday == 1 ? 7 : isoWeekday - 1
        let sessions: [JSONValue] = plan.sessions.sorted { $0.weekday < $1.weekday }.map { session in
            var fields: [String: JSONValue] = [
                "weekday": .number(Double(session.weekday)),
                "dayName": .string(Self.weekdayNames[(session.weekday - 1) % 7]),
                "title": .string(session.title),
                "status": .string((healthConsent || session.status != .adapted ? session.status : .planned).rawValue),
                "today": .bool(session.weekday == today),
                "exercises": .array(session.exercises.map(exercise)),
            ]
            if healthConsent, let note = session.adaptationNote { fields["adaptationNote"] = .string(note) }
            return .object(fields)
        }
        return CoachToolOutput(content: Self.json(["source": .string(plan.source.rawValue), "sessions": .array(sessions)]),
                               sourceLabel: "plan treningowy")
    }

    private func exercise(_ planned: PlannedExercise) -> JSONValue {
        let timed = catalog.exercise(id: planned.exerciseId)?.timed ?? false
        let range = planned.repsMin == planned.repsMax ? "\(planned.repsMin)" : "\(planned.repsMin)–\(planned.repsMax)"
        var fields: [String: JSONValue] = [
            "exerciseId": .string(planned.exerciseId),
            "name": .string(name(of: planned.exerciseId)),
            "sets": .number(Double(planned.sets)),
            (timed ? "durationSeconds" : "reps"): .string(range),
            "restSeconds": .number(Double(planned.restSeconds)),
        ]
        if let tempo = planned.tempo { fields["tempo"] = .string(tempo.label) }
        return .object(fields)
    }

    // MARK: technique

    private func techniqueHistory(_ input: JSONValue) async -> CoachToolOutput {
        let limit = Self.clamp(input["limit"]?.intValue ?? 5, 1, 10)
        let wanted = input["exerciseId"]?.stringValue
        let results = await technique.results(limit: 30).filter { wanted == nil || $0.exerciseId == wanted }.prefix(limit)
        let sets = await technique.setSummaries(limit: 30).filter { wanted == nil || $0.exerciseId == wanted }.prefix(limit)

        let analyses: [JSONValue] = results.map { result in
            var fields: [String: JSONValue] = [
                "exerciseId": .string(result.exerciseId),
                "exercise": .string(name(of: result.exerciseId)),
                "date": .string(day(result.date)),
                "score": .number(Double(result.score)),
                "components": .object(result.componentScores.mapValues { .number(Double($0)) }),
                "findings": .array(result.findings.map { finding in
                    .object(["title": .string(finding.title), "detail": .string(finding.detail),
                             "severity": .string(finding.severity.rawValue),
                             "repsAffected": .number(Double(finding.repsAffected)),
                             "repsTotal": .number(Double(finding.repsTotal))])
                }),
            ]
            if let substitute = result.substituteExerciseId { fields["suggestedSubstitute"] = .string(name(of: substitute)) }
            if result.isSimulated { fields["isSimulated"] = .bool(true) }
            return .object(fields)
        }
        let liveSets: [JSONValue] = sets.map { set in
            var fields: [String: JSONValue] = [
                "exerciseId": .string(set.exerciseId),
                "exercise": .string(name(of: set.exerciseId)),
                "date": .string(day(set.date)),
                "setIndex": .number(Double(set.setIndex)),
                "reps": .number(Double(set.reps.count)),
                "targetTempo": .string(set.targetTempo.label),
                "tempoScore": .number(Double(set.tempoScore)),
                "tempoFindings": .array(set.tempoFindings.map { .string($0.title + ": " + $0.detail) }),
            ]
            if let score = set.techniqueScore { fields["techniqueScore"] = .number(Double(score)) }
            if set.isSimulated { fields["isSimulated"] = .bool(true) }
            return .object(fields)
        }
        let simulated = results.contains { $0.isSimulated } || sets.contains { $0.isSimulated }
        let content = Self.json(["analyses": .array(analyses), "liveSets": .array(liveSets)])
        return CoachToolOutput(content: content, sourceLabel: wanted.map { "analizy techniki: \(name(of: $0))" } ?? "analizy techniki",
                               isSimulated: simulated)
    }

    // MARK: health data (consent already checked)

    private func todayRecommendation() async -> CoachToolOutput {
        let rec = await recommendation.todayRecommendation()
        var fields: [String: JSONValue] = [
            "decision": .string(rec.decision.rawValue),
            "decisionLabel": .string(rec.decision.title),
            "headline": .string(rec.headline),
            "factors": .array(rec.factors.map {
                .object(["source": .string($0.source.rawValue), "text": .string($0.text),
                         "pushesTowardsLighterDay": .bool($0.isNegative)])
            }),
            "suggestedAction": .string(rec.suggestedAction),
        ]
        if let care = rec.careFlag { fields["careSignal"] = .string(care.reason) }
        if rec.isSimulated { fields["isSimulated"] = .bool(true) }
        return CoachToolOutput(content: Self.json(fields), sourceLabel: "rekomendacja dnia", isSimulated: rec.isSimulated)
    }

    private func recoverySummary(days: Int) async -> CoachToolOutput {
        let snapshots = await recovery.snapshots(days: days)
        guard let latest = snapshots.first else {
            return CoachToolOutput(content: Self.json(["days": .number(0), "note": .string("Brak danych o regeneracji.")]),
                                   sourceLabel: "regeneracja")
        }
        func average(_ values: [Int]) -> Double { Double(values.reduce(0, +)) / Double(values.count) }
        let percent = (latest.hrvDeltaRatio * 100).rounded()
        var fields: [String: JSONValue] = [
            "days": .number(Double(snapshots.count)),
            "lastNight": .object(["date": .string(day(latest.date)), "sleepMinutes": .number(Double(latest.sleepMinutes))]),
            "sleepAverageMinutes": .number(average(snapshots.map(\.sleepMinutes)).rounded()),
            "hrv": .object(["lastMs": .number(Double(latest.hrvMs)), "baselineMs": .number(Double(latest.hrvBaselineMs)),
                            "percentVsBaseline": .number(percent)]),
            "restingHeartRate": .object(["last": .number(Double(latest.restingHeartRate)),
                                         "baseline": .number(Double(latest.restingHeartRateBaseline))]),
            "daily": .array(snapshots.map {
                .object(["date": .string(day($0.date)), "sleepMinutes": .number(Double($0.sleepMinutes)),
                         "hrvMs": .number(Double($0.hrvMs)), "restingHeartRate": .number(Double($0.restingHeartRate))])
            }),
        ]
        let simulated = snapshots.contains { $0.isSimulated }
        if simulated { fields["isSimulated"] = .bool(true) }
        return CoachToolOutput(content: Self.json(fields), sourceLabel: "regeneracja z \(snapshots.count) \(Self.dayWord(snapshots.count))",
                               isSimulated: simulated)
    }

    private func recentCheckIns(days: Int) async -> CoachToolOutput {
        let entries = await checkIns.checkIns(days: days)
        guard !entries.isEmpty else {
            return CoachToolOutput(content: Self.json(["checkIns": .array([]), "note": .string("Brak check-inów z tego okresu.")]),
                                   sourceLabel: "check-iny")
        }
        func average(_ values: [Int]) -> Double { (Double(values.reduce(0, +)) / Double(values.count) * 10).rounded() / 10 }
        let list: [JSONValue] = entries.map {
            .object(["date": .string(day($0.date)), "mood": .number(Double($0.mood)), "stress": .number(Double($0.stress)),
                     "energy": .number(Double($0.energy))])  // the free-text note is never included
        }
        let fields: [String: JSONValue] = [
            "scale": .string("1-5"),
            "checkIns": .array(list),
            "average": .object(["mood": .number(average(entries.map(\.mood))), "stress": .number(average(entries.map(\.stress))),
                                "energy": .number(average(entries.map(\.energy)))]),
        ]
        return CoachToolOutput(content: Self.json(fields), sourceLabel: "check-iny z \(days) \(Self.dayWord(days))")
    }

    private func recentSessionFeedback(limit: Int) async -> CoachToolOutput {
        guard let feedback else {
            return CoachToolOutput(content: Self.json(["workouts": .array([]), "note": .string("Brak danych o feedbacku po treningach.")]),
                                   sourceLabel: "feedback po treningach")
        }
        let entries = await feedback.feedbacks(limit: limit)
        guard !entries.isEmpty else {
            return CoachToolOutput(content: Self.json(["workouts": .array([]), "note": .string("Brak feedbacku po treningach.")]),
                                   sourceLabel: "feedback po treningach")
        }
        let list: [JSONValue] = entries.map { entry in
            var fields: [String: JSONValue] = [
                "date": .string(day(entry.date)),
                "rpe": .number(Double(entry.perceivedExertion)),
                "completedSets": .number(Double(entry.completedSets)),
                "plannedSets": .number(Double(entry.plannedSets)),
                // Where it hurt and how much; the free-text note is never included.
                "discomfort": .array(entry.pain.map {
                    .object(["area": .string($0.area.title), "intensity": .number(Double($0.intensity))])
                }),
            ]
            if let enjoyment = entry.enjoyment { fields["enjoyment1to5"] = .number(Double(enjoyment)) }
            if entry.isSimulated { fields["isSimulated"] = .bool(true) }
            return .object(fields)
        }
        let average = (Double(entries.map(\.perceivedExertion).reduce(0, +)) / Double(entries.count) * 10).rounded() / 10
        let fields: [String: JSONValue] = ["rpeScale": .string("1-10"), "workouts": .array(list), "averageRpe": .number(average)]
        let simulated = entries.contains { $0.isSimulated }
        return CoachToolOutput(content: Self.json(fields), sourceLabel: "feedback po treningach", isSimulated: simulated)
    }

    // MARK: helpers

    private static func days(_ input: JSONValue, default value: Int) -> Int {
        clamp(input["days"]?.intValue ?? value, 1, 14)
    }

    private static func clamp(_ value: Int, _ low: Int, _ high: Int) -> Int { min(max(value, low), high) }

    private static func dayWord(_ n: Int) -> String { n == 1 ? "dnia" : "dni" }

    private func day(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func json(_ fields: [String: JSONValue]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(JSONValue.object(fields)), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}
