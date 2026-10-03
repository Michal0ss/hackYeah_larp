import Contracts
import Foundation

/// Builds a weekly plan from the templates and the catalog, with no model and no network. It is the same algorithm as
/// the backend's `build_template_plan` (backend/app/services/plan_builder.py), and a test compares the two on a grid of
/// profiles, so what the phone builds offline is what the server would have built.
///
/// For each session of the week it takes the movement patterns of the session kind (squat, push, pull, ...), picks one
/// catalog exercise per pattern that fits the user's equipment, level and avoided movements, and prescribes sets and
/// reps for the goal.
public struct TemplatePlanBuilder: Sendable {
    private let templates: PlanTemplates
    private let catalog: [ExerciseItem]

    public init(templates: PlanTemplates, catalog: [ExerciseItem]) {
        self.templates = templates
        self.catalog = catalog
    }

    /// Nil only when the templates have nothing for this goal or number of days.
    public func build(for profile: UserProfile, now: Date = Date()) -> TrainingPlan? {
        let days = min(max(profile.daysPerWeek, 2), 5)
        guard let scheme = templates.goals[profile.goal.rawValue],
              let weekdays = templates.weekdays[String(days)],
              let kinds = templates.sessionsByDays[String(days)],
              weekdays.count == kinds.count else { return nil }

        let allowed = PlanRules.allowed(in: catalog, for: profile, scheme: scheme)
        let perSession = templates.exercisesPerSession(forMinutes: profile.sessionMinutes)

        var sessions: [PlannedSession] = []
        var seenKinds: [String: Int] = [:]
        for (weekday, kind) in zip(weekdays, kinds) {
            guard let blueprint = templates.blueprints[kind] else { return nil }
            let occurrence = seenKinds[kind, default: 0]
            seenKinds[kind] = occurrence + 1

            let slots = blueprint.slots.filter { !scheme.dropSlots.contains($0) }.prefix(perSession)
            var picked: [ExerciseItem] = []
            var used: Set<String> = []
            for slot in slots {
                let candidates = allowed.filter { $0.pattern == slot }
                if let exercise = pick(from: candidates, preference: scheme.equipmentPreference, occurrence: occurrence, used: used) {
                    picked.append(exercise)
                    used.insert(exercise.id)
                }
            }
            if picked.isEmpty {
                // Everything for this session was filtered out: one gentle core exercise beats an empty day.
                let core = allowed.filter { $0.pattern == "core" }
                if let fallback = pick(from: core.isEmpty ? allowed : core, preference: "lowest", occurrence: 0, used: used) {
                    picked.append(fallback)
                }
            }
            let letter = Character(UnicodeScalar(UInt8(65 + min(occurrence, 25))))
            sessions.append(PlannedSession(
                weekday: weekday,
                title: occurrence == 0 ? blueprint.title : "\(blueprint.title) \(letter)",
                exercises: picked.map { prescribe($0, scheme: scheme, profile: profile) }
            ))
        }
        return TrainingPlan(createdAt: now, source: .template, sessions: sessions)
    }

    /// Among the unused candidates, the ones with the highest (or lowest) equipment need; rotating inside that tier
    /// by `occurrence`, so a second "lower body" session is not identical to the first.
    private func pick(from candidates: [ExerciseItem], preference: String, occurrence: Int, used: Set<String>) -> ExerciseItem? {
        let pool = candidates.filter { !used.contains($0.id) }
        let ranks = pool.map(\.equipment.planRank)
        guard let target = preference == "highest" ? ranks.max() : ranks.min() else { return nil }
        let tier = zip(pool, ranks).filter { $0.1 == target }.map(\.0)
        return tier[occurrence % tier.count]
    }

    private func prescribe(_ exercise: ExerciseItem, scheme: PlanTemplates.GoalScheme, profile: UserProfile) -> PlannedExercise {
        var sets: Int, repsMin: Int, repsMax: Int, rest: Int
        if exercise.timed ?? false {
            let timed = templates.timedScheme
            (sets, repsMin, repsMax, rest) = (min(scheme.sets, 3), timed.repsMin, timed.repsMax, timed.restSeconds)
        } else {
            (sets, repsMin, repsMax, rest) = (scheme.sets, scheme.repsMin, scheme.repsMax, scheme.restSeconds)
        }
        if profile.easyStart { sets = max(2, sets - 1) }
        return PlannedExercise(exerciseId: exercise.id, sets: sets, repsMin: repsMin, repsMax: repsMax,
                               restSeconds: rest, tempo: exercise.defaultTempo)
    }
}
