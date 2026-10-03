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

    public init(plan: PlanProviding, catalog: ExerciseCatalogProviding, profile: @escaping @Sendable () async -> UserProfile) {
        self.plan = plan
        self.catalog = catalog
        self.profile = profile
    }

    public func propose(_ input: JSONValue) async -> CoachToolOutput {
        guard let plan = await plan.currentPlan() else {
            return Self.failure("Użytkownik nie ma jeszcze planu.")
        }
        guard let kind = Self.kind(input["kind"]?.stringValue) else {
            return Self.failure("Nieznany rodzaj zmiany. Dozwolone: swap_exercise, lighter_session, move_session, skip_session.")
        }
        let changer = PlanChanger(catalog: catalog.exercises, profile: await profile())
        do {
            let proposal = try changer.propose(kind: kind, weekday: input["weekday"]?.intValue,
                                               exerciseId: input["exerciseId"]?.stringValue,
                                               replacementExerciseId: input["replacementExerciseId"]?.stringValue,
                                               newWeekday: input["newWeekday"]?.intValue,
                                               reason: input["reason"]?.stringValue, in: plan)
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

    /// What the model needs to try again: the days and exercises that exist in the plan.
    private func hint(for error: PlanChangeError, in plan: TrainingPlan) -> [String: JSONValue] {
        switch error {
        case .noSuchSession, .dayTaken, .sameDay:
            let sessions = plan.window(from: Date()).map {
                JSONValue.object(["weekday": .number(Double($0.weekday)), "title": .string($0.title)])
            }
            return ["sessionsInPlan": .array(sessions)]
        case .noSuchExercise:
            return ["exercisesInPlan": .array(plan.window(from: Date()).map { session in
                .object(["weekday": .number(Double(session.weekday)),
                         "exerciseIds": .array(session.exercises.map { .string($0.exerciseId) })])
            })]
        default:
            return [:]
        }
    }

    private static func kind(_ raw: String?) -> PlanChangeKind? {
        switch raw {
        case "swap_exercise": return .swapExercise
        case "lighter_session": return .lighterSession
        case "move_session": return .moveSession
        case "skip_session": return .skipSession
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
