import API
import Contracts
import Foundation
import Plan

/// Turns the model's `propose_plan_change` call into a proposal card, or into an error the model can read and explain.
///
/// It never changes anything: it reads the plan, checks the request with `PlanChanger` and returns the proposal. The
/// plan changes only when the user accepts the card (`PlanChangeApplying`).
public struct PlanChangeProposer: Sendable {
    /// The plan as planned, NOT as adjusted for today: a change is made on the plan itself, and an adjustment made by
    /// the rule engine (derived from health data) must not be saved into it.
    private let plan: PlanProviding
    private let catalog: ExerciseCatalogProviding
    private let profile: @Sendable () async -> UserProfile
    private let now: @Sendable () -> Date

    public init(plan: PlanProviding, catalog: ExerciseCatalogProviding, profile: @escaping @Sendable () async -> UserProfile,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.plan = plan
        self.catalog = catalog
        self.profile = profile
        self.now = now
    }

    public func propose(_ input: JSONValue) async -> CoachToolOutput {
        guard let plan = await plan.currentPlan() else {
            return Self.failure("Użytkownik nie ma jeszcze planu.")
        }
        guard let kind = Self.kind(input["kind"]?.stringValue) else {
            return Self.failure("Nieznany rodzaj zmiany. Dozwolone: swap_exercise, lighter_session, move_session, skip_session, add_exercise, remove_exercise, edit_exercise.")
        }
        let changer = PlanChanger(catalog: catalog.exercises, profile: await profile(), now: now)
        // A date the model wrote must be a real day (2026-10-14): a garbled one is an error it can fix, not a guess.
        var date: Date?
        if let text = input["date"]?.stringValue {
            guard let parsed = PlanChanger.parseDay(text) else {
                return Self.failure("Nieprawidłowa data sesji. Użyj formatu RRRR-MM-DD, z daty widocznej w planie.",
                                    hint: hint(for: .noSuchSession, in: plan))
            }
            date = parsed
        }
        var newDate: Date?
        if let text = input["newDate"]?.stringValue {
            guard let parsed = PlanChanger.parseDay(text) else {
                return Self.failure("Nieprawidłowa nowa data. Użyj formatu RRRR-MM-DD.", hint: hint(for: .noSuchSession, in: plan))
            }
            newDate = parsed
        }
        do {
            let proposal = try changer.propose(kind: kind, weekday: input["weekday"]?.intValue,
                                               exerciseId: input["exerciseId"]?.stringValue,
                                               replacementExerciseId: input["replacementExerciseId"]?.stringValue,
                                               newWeekday: input["newWeekday"]?.intValue,
                                               reason: input["reason"]?.stringValue,
                                               sets: input["sets"]?.intValue, repsMin: input["repsMin"]?.intValue,
                                               repsMax: input["repsMax"]?.intValue,
                                               restSeconds: input["restSeconds"]?.intValue, date: date, newDate: newDate,
                                               in: plan)
            let fields: [String: JSONValue] = [
                "status": .string("proposed"),
                "summary": .string(proposal.summary),
                "note": .string("Karta z propozycją czeka na decyzję użytkownika pod Twoją odpowiedzią. Plan jeszcze się nie zmienił: nie pisz, że jest zmieniony."),
            ]
            return CoachToolOutput(content: Self.json(fields), proposal: proposal)
        } catch let error as PlanChangeError {
            return Self.failure(error.message, hint: hint(for: error, in: plan))
        } catch {
            return Self.failure("Nie udało się przygotować propozycji.")
        }
    }

    /// What the model needs to try again: the days (with dates) and exercises that exist in the plan.
    private func hint(for error: PlanChangeError, in plan: TrainingPlan) -> [String: JSONValue] {
        switch error {
        case .noSuchSession, .dayTaken, .sameDay, .outsidePlan:
            return ["sessionsInPlan": .array(upcoming(plan).map {
                var fields: [String: JSONValue] = ["weekday": .number(Double($0.weekday)), "title": .string($0.title)]
                if let date = $0.date { fields["date"] = .string(Self.day(date)) }
                return .object(fields)
            })]
        case .noSuchExercise:
            return ["exercisesInPlan": .array(upcoming(plan).map { session in
                var fields: [String: JSONValue] = ["weekday": .number(Double(session.weekday)),
                                                   "exerciseIds": .array(session.exercises.map { .string($0.exerciseId) })]
                if let date = session.date { fields["date"] = .string(Self.day(date)) }
                return .object(fields)
            })]
        default:
            return [:]
        }
    }

    /// The next sessions the model may name: the coming two weeks of a dated plan, the whole pattern otherwise.
    private func upcoming(_ plan: TrainingPlan) -> [PlannedSession] {
        guard plan.isDated else { return plan.window(from: now()) }
        let calendar = TrainingPlan.calendar
        let start = calendar.startOfDay(for: now())
        guard let end = calendar.date(byAdding: .day, value: 14, to: start) else { return [] }
        return plan.chronological.filter { ($0.date ?? start) >= start && ($0.date ?? end) < end }
    }

    private static func day(_ date: Date) -> String {
        let parts = TrainingPlan.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func kind(_ raw: String?) -> PlanChangeKind? {
        switch raw {
        case "swap_exercise": return .swapExercise
        case "lighter_session": return .lighterSession
        case "move_session": return .moveSession
        case "skip_session": return .skipSession
        case "add_exercise": return .addExercise
        case "remove_exercise": return .removeExercise
        case "edit_exercise": return .editExercise
        default: return nil
        }
    }

    private static func failure(_ message: String, hint: [String: JSONValue] = [:]) -> CoachToolOutput {
        CoachToolOutput(content: json(hint.merging(["error": .string(message)]) { current, _ in current }), isError: true)
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

/// Makes an accepted proposal real: changes the plan, saves it, and tells the screens. Implemented by the app.
public protocol PlanChangeApplying: Sendable {
    func apply(_ proposal: PlanChangeProposal) async -> Result<PlanChangeProposal, PlanChangeError>
    func undo(_ proposal: PlanChangeProposal) async -> Result<PlanChangeProposal, PlanChangeError>
}
