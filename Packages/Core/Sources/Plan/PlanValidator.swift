import Contracts
import Foundation

/// What is wrong with a plan. Short codes, so they can be logged and tested.
public enum PlanIssue: String, Sendable, Equatable {
    case wrongSessionCount, duplicateWeekday, badWeekday, badExerciseCount, repeatedExercise
    case unknownExercise, avoidedMovement, equipmentNotAvailable, levelTooHigh
    case badSets, tooManySets, badRepRange, tooManyReps, badDuration
}

/// Checks a plan against the user's profile and the catalog. The same rules the server applies to a plan from the
/// model (backend/app/services/plan_validator.py), run again on the phone: the model proposes, the app decides.
public enum PlanValidator {
    static let maxExercisesPerSession = 8
    static let maxSets = 6
    static let maxReps = 30
    static let timedReps = 10...120

    public static func validate(_ plan: TrainingPlan, profile: UserProfile, catalog: [ExerciseItem],
                                templates: PlanTemplates? = nil) -> [PlanIssue] {
        var issues: Set<PlanIssue> = []
        let byId = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let scheme = templates?.goals[profile.goal.rawValue]
        let maxLevel = PlanRules.effectiveLevel(for: profile, scheme: scheme)
        let blocked = Set(profile.avoidTags)

        if plan.sessions.count != profile.daysPerWeek { issues.insert(.wrongSessionCount) }
        let weekdays = plan.sessions.map(\.weekday)
        if Set(weekdays).count != weekdays.count { issues.insert(.duplicateWeekday) }
        if weekdays.contains(where: { !(1...7).contains($0) }) { issues.insert(.badWeekday) }

        for session in plan.sessions {
            if !(1...maxExercisesPerSession).contains(session.exercises.count) { issues.insert(.badExerciseCount) }
            let ids = session.exercises.map(\.exerciseId)
            if Set(ids).count != ids.count { issues.insert(.repeatedExercise) }
            for planned in session.exercises {
                guard let item = byId[planned.exerciseId] else {
                    issues.insert(.unknownExercise)
                    continue
                }
                if !blocked.isDisjoint(with: item.movementTags ?? []) { issues.insert(.avoidedMovement) }
                if item.equipment.planRank > profile.equipment.planRank { issues.insert(.equipmentNotAvailable) }
                if item.level.planRank > maxLevel.planRank { issues.insert(.levelTooHigh) }
                if planned.sets < 1 { issues.insert(.badSets) }
                if planned.sets > maxSets { issues.insert(.tooManySets) }
                if planned.repsMin < 1 || planned.repsMin > planned.repsMax { issues.insert(.badRepRange) }
                if item.timed ?? false {
                    if !timedReps.contains(planned.repsMin) || !timedReps.contains(planned.repsMax) { issues.insert(.badDuration) }
                } else if planned.repsMax > maxReps {
                    issues.insert(.tooManyReps)
                }
            }
        }
        return issues.sorted { $0.rawValue < $1.rawValue }
    }
}
