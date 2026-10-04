import Content
import Contracts
import Foundation

/// The rules for building a plan without a model: which weekdays, which kinds of session, which movement patterns
/// fill a session, and sets and reps per goal. Read from `content/plan_templates.json` (the bundled copy), the same
/// file the backend uses, so the plan built on the phone matches the plan the server falls back to.
public struct PlanTemplates: Codable, Equatable, Sendable {
    public struct Blueprint: Codable, Equatable, Sendable {
        public var title: String
        /// Movement patterns (`squat`, `hinge`, `lunge`, `push`, `pull`, `core`, `cardio`), one exercise each.
        public var slots: [String]
        /// The slots of a session of `PlanTemplates.longSessionMinutes` or more (more exercises than `slots` holds).
        public var longSlots: [String]?
    }

    /// From this length of a session on, a blueprint's `longSlots` are used.
    public static let longSessionMinutes = 90

    public struct GoalScheme: Codable, Equatable, Sendable {
        public var sets: Int
        public var repsMin: Int
        public var repsMax: Int
        public var restSeconds: Int
        public var dropSlots: [String]
        /// "highest" prefers exercises that need more equipment, "lowest" the simplest ones.
        public var equipmentPreference: String
        public var forceLevel: String?
    }

    public struct TimedScheme: Codable, Equatable, Sendable {
        public var repsMin: Int
        public var repsMax: Int
        public var restSeconds: Int
    }

    public var version: Int
    /// Keys are the number of days per week ("2"..."5").
    public var weekdays: [String: [Int]]
    public var sessionsByDays: [String: [String]]
    public var blueprints: [String: Blueprint]
    /// Keys are session minutes ("30", "45", ...).
    public var exercisesPerSession: [String: Int]
    /// Keys are `TrainingGoal` raw values.
    public var goals: [String: GoalScheme]
    public var timedScheme: TimedScheme

    public static func decode(_ data: Data) -> PlanTemplates? {
        try? JSONDecoder().decode(PlanTemplates.self, from: data)
    }

    /// The copy bundled in the app. Nil only if the resource is missing or broken.
    public static func bundled() -> PlanTemplates? {
        ContentRepository.bundledPlanTemplates().flatMap(decode)
    }

    /// Exercises in one session: the largest configured duration that fits into `minutes`, or the shortest one.
    func exercisesPerSession(forMinutes minutes: Int) -> Int {
        let keys = exercisesPerSession.keys.compactMap(Int.init).sorted()
        guard let shortest = keys.first else { return 4 }
        let fitting = keys.last { $0 <= minutes } ?? shortest
        return exercisesPerSession[String(fitting)] ?? 4
    }
}

// Ranks used to compare what a user can do with what an exercise needs.
extension Equipment {
    var planRank: Int {
        switch self {
        case .none: return 0
        case .dumbbells: return 1
        case .gym: return 2
        }
    }
}

extension TrainingLevel {
    var planRank: Int {
        switch self {
        case .beginner: return 0
        case .intermediate: return 1
        }
    }
}

enum PlanRules {
    /// The easiest of: the user's level, the level the goal forces and "beginner" for an easy start.
    static func effectiveLevel(for profile: UserProfile, scheme: PlanTemplates.GoalScheme?) -> TrainingLevel {
        var levels = [profile.level]
        if let forced = scheme?.forceLevel.flatMap(TrainingLevel.init(rawValue:)) { levels.append(forced) }
        if profile.easyStart { levels.append(.beginner) }
        return levels.min { $0.planRank < $1.planRank } ?? profile.level
    }

    /// Catalog exercises the user can do: within the equipment and level, without the avoided movements.
    static func allowed(in catalog: [ExerciseItem], for profile: UserProfile, scheme: PlanTemplates.GoalScheme?) -> [ExerciseItem] {
        let level = effectiveLevel(for: profile, scheme: scheme)
        let blocked = Set(profile.avoidTags)
        return catalog.filter { item in
            item.equipment.planRank <= profile.equipment.planRank
                && item.level.planRank <= level.planRank
                && blocked.isDisjoint(with: item.movementTags ?? [])
        }
    }
}
