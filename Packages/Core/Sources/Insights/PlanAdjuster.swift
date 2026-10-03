import Foundation
import Contracts

/// Result of applying the daily decision to a planned session.
public struct PlanAdjustment: Equatable, Sendable {
    /// The session as planned. Keep it: the user can restore it ("Przywróć oryginał") and tomorrow's
    /// decision starts again from it, never from an already adjusted session.
    public var original: PlannedSession
    /// What to show and do today. Equals `original` when nothing changed.
    public var session: PlannedSession
    /// Human readable lines for the "what changed" list, in Polish.
    public var changes: [String]
    public var isRestDay: Bool

    public var isChanged: Bool { !changes.isEmpty }

    public init(original: PlannedSession, session: PlannedSession, changes: [String], isRestDay: Bool) {
        self.original = original
        self.session = session
        self.changes = changes
        self.isRestDay = isRestDay
    }
}

/// Changes today's session according to the decision from the rule engine (PROJECT.md 7.2). Pure and deterministic,
/// uses only catalog exercises.
///
/// - **Trenuj**: unchanged.
/// - **Zmodyfikuj**: one set less in every exercise that has more than two, rests shortened by a quarter
///   (rounded to 15 s, never under 30 s), and, when the technique analysis raised a signal, the analysed exercise
///   is swapped for the substitute from that analysis (only if it is in the catalog, not already in the session
///   and within the user's equipment). Reps stay as planned.
/// - **Odpuść**: the session becomes a rest day (no exercises), with a light walk or mobility as the suggestion.
///
/// A session that is already done or already adjusted is returned untouched, so applying the adjuster twice never
/// lightens a session twice. Always pass the original session.
public struct PlanAdjuster: Sendable {
    public static let restDayTitle = "Dzień odpoczynku"

    public var catalog: [ExerciseItem]

    public init(catalog: [ExerciseItem]) {
        self.catalog = catalog
    }

    public func adjust(_ session: PlannedSession, for recommendation: DailyRecommendation,
                       technique: TechniqueResult? = nil, equipment: Equipment? = nil) -> PlanAdjustment {
        guard session.status == .planned else { return unchanged(session) }
        switch recommendation.decision {
        case .train: return unchanged(session)
        case .rest: return restDay(session, recommendation)
        case .adapt: return lighter(session, recommendation, technique: technique, equipment: equipment)
        }
    }

    // MARK: Decisions

    private func restDay(_ session: PlannedSession, _ recommendation: DailyRecommendation) -> PlanAdjustment {
        var rest = session
        rest.title = Self.restDayTitle
        rest.exercises = []
        rest.status = .adapted
        rest.adaptationNote = "Regeneracja: \(Self.reasons(recommendation)). Lekki spacer albo kilka minut mobilności wystarczą."
        return PlanAdjustment(original: session, session: rest,
                              changes: ["Sesja „\(session.title)” zamieniona na odpoczynek"], isRestDay: true)
    }

    private func lighter(_ session: PlannedSession, _ recommendation: DailyRecommendation,
                         technique: TechniqueResult?, equipment: Equipment?) -> PlanAdjustment {
        let techniqueSignal = recommendation.factors.contains { $0.source == .technique && $0.isNegative }
        var changes: [String] = []
        var exercises: [PlannedExercise] = []
        var usedSubstitutes = Set<String>()

        for original in session.exercises {
            var ex = original
            let sets = original.sets > 2 ? original.sets - 1 : original.sets
            let rest = Self.shortenedRest(original.restSeconds)
            var parts: [String] = []
            if sets != original.sets {
                ex.sets = sets
                parts.append("\(original.sets) → \(sets) \(Self.setsWord(sets))")
            }
            if rest != original.restSeconds {
                ex.restSeconds = rest
                parts.append("przerwa \(Self.clock(original.restSeconds)) → \(Self.clock(rest))")
            }

            if techniqueSignal, let technique, technique.exerciseId == original.exerciseId,
               let sub = substitute(for: technique, in: session, equipment: equipment),
               !usedSubstitutes.contains(sub.id) {
                usedSubstitutes.insert(sub.id)
                ex.exerciseId = sub.id
                ex.tempo = sub.defaultTempo ?? original.tempo
                changes.append("\(name(original.exerciseId)) zastąpiony: \(Self.lowercasedFirst(sub.name))"
                               + (parts.isEmpty ? "" : ", " + parts.joined(separator: ", ")))
            } else if !parts.isEmpty {
                changes.append("\(name(original.exerciseId)): \(parts.joined(separator: ", "))")
            }
            exercises.append(ex)
        }

        guard !changes.isEmpty else { return unchanged(session) }
        var adjusted = session
        adjusted.exercises = exercises
        adjusted.status = .adapted
        adjusted.adaptationNote = "Lżejszy trening: \(Self.reasons(recommendation))."
        return PlanAdjustment(original: session, session: adjusted, changes: changes, isRestDay: false)
    }

    private func unchanged(_ session: PlannedSession) -> PlanAdjustment {
        PlanAdjustment(original: session, session: session, changes: [], isRestDay: false)
    }

    // MARK: Substitute

    private func substitute(for technique: TechniqueResult, in session: PlannedSession, equipment: Equipment?) -> ExerciseItem? {
        guard let id = technique.substituteExerciseId, let item = catalog.first(where: { $0.id == id }),
              !session.exercises.contains(where: { $0.exerciseId == id }) else { return nil }
        if let equipment, Self.rank(item.equipment) > Self.rank(equipment) { return nil }
        return item
    }

    private static func rank(_ e: Equipment) -> Int {
        switch e {
        case .none: return 0
        case .dumbbells: return 1
        case .gym: return 2
        }
    }

    // MARK: Texts and numbers

    private func name(_ id: String) -> String { catalog.first { $0.id == id }?.name ?? id }

    /// Reasons from the negative factors, in plain words, without numbers or medical wording.
    static func reasons(_ recommendation: DailyRecommendation) -> String {
        let order: [FactorSource] = [.sleep, .hrv, .restingHeartRate, .checkIn, .technique]
        let words: [FactorSource: String] = [
            .sleep: "krótki sen",
            .hrv: "HRV niżej niż zwykle",
            .restingHeartRate: "podwyższone tętno spoczynkowe",
            .checkIn: "podwyższony stres lub niska energia",
            .technique: "uwagi do techniki",
        ]
        let present = order.filter { s in recommendation.factors.contains { $0.source == s && $0.isNegative } }
            .compactMap { words[$0] }
        switch present.count {
        case 0: return "sygnały z dzisiejszych danych"
        case 1: return present[0]
        default: return present.dropLast().joined(separator: ", ") + " i " + present[present.count - 1]
        }
    }

    /// 25% shorter, rounded to 15 s, never under 30 s and never longer than before.
    static func shortenedRest(_ seconds: Int) -> Int {
        guard seconds > 30 else { return seconds }
        let rounded = Int((Double(seconds) * 0.75 / 15).rounded()) * 15
        return min(seconds, max(30, rounded))
    }

    static func clock(_ seconds: Int) -> String { "\(seconds / 60):" + String(format: "%02d", seconds % 60) }

    /// Polish plural: 1 seria, 2-4 serie, 5+ serii.
    static func setsWord(_ n: Int) -> String {
        if n == 1 { return "seria" }
        let lastTwo = n % 100, last = n % 10
        return (2...4).contains(last) && !(12...14).contains(lastTwo) ? "serie" : "serii"
    }

    private static func lowercasedFirst(_ s: String) -> String { InsightEngine.lowercasedFirst(s) }
}
