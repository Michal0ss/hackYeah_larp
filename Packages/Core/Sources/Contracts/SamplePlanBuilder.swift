import Foundation

/// Builds a plausible weekly plan from the sample sessions. Used by `SampleServices` until the real
/// `PlanGenerating` implementation (Maciek) is plugged in. It honors days per week, `avoidTags` and `easyStart`
/// only as far as the sample catalog allows.
enum SamplePlanBuilder {
    /// Training weekdays (1 = Monday) for a number of days per week.
    static let weekdays: [Int: [Int]] = [2: [1, 4], 3: [1, 3, 5], 4: [1, 2, 4, 5], 5: [1, 2, 3, 5, 6]]

    /// Sample catalog exercises that belong to a movement pattern. Tags without a match
    /// (jumps, barbell deadlift, loaded push-ups) leave the sample plan unchanged.
    static func exerciseIds(for tag: MovementTag) -> [String] {
        switch tag {
        case .deepLunges: return ["lunge"]
        case .overheadPress: return ["overhead_press"]
        case .deepSquats: return ["squat"]
        case .jumps, .barbellDeadlift, .loadedPushups: return []
        }
    }

    static func plan(for profile: UserProfile, now: Date = Date()) -> TrainingPlan {
        let days = min(max(profile.daysPerWeek, 2), 5)
        let templates = SampleData.plan.sessions.sorted { $0.weekday < $1.weekday }
        let blocked = Set(profile.avoidTags.flatMap(exerciseIds(for:)))
        let fallback = PlannedExercise(exerciseId: "plank", sets: 3, repsMin: 30, repsMax: 45, restSeconds: 45)

        let sessions: [PlannedSession] = (weekdays[days] ?? weekdays[3]!).enumerated().map { index, weekday in
            let template = templates[index % templates.count]
            var exercises = template.exercises.filter { !blocked.contains($0.exerciseId) }
            if exercises.isEmpty { exercises = [fallback] }
            if profile.easyStart {
                exercises = exercises.map { exercise in
                    var lighter = exercise
                    lighter.sets = max(2, exercise.sets - 1)
                    return lighter
                }
            }
            let title = index >= templates.count ? "\(template.title) B" : template.title
            return PlannedSession(weekday: weekday, title: title, exercises: exercises)
        }
        return TrainingPlan(createdAt: now, source: .template, sessions: sessions)
    }
}
