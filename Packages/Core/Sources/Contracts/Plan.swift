import Foundation

public enum TrainingGoal: String, Codable, Sendable, CaseIterable {
    case strength, physique, fitness, returnToMovement
}

public enum TrainingLevel: String, Codable, Sendable, CaseIterable {
    case beginner, intermediate
}

public enum Equipment: String, Codable, Sendable, CaseIterable {
    case none, dumbbells, gym
}

/// What the user has at hand. Onboarding is a multi-select; `Equipment` is the tier derived from it.
public enum GearItem: String, Codable, Sendable, CaseIterable {
    case none, dumbbells, kettlebell, gym
}

public extension Equipment {
    /// Best tier for a selection: gym > dumbbells or kettlebell > none.
    static func resolve(from gear: [GearItem]) -> Equipment {
        if gear.contains(.gym) { return .gym }
        if gear.contains(.dumbbells) || gear.contains(.kettlebell) { return .dumbbells }
        return .none
    }
}

/// Movement patterns the plan should leave out. Onboarding derives them from what the user reported;
/// the plan generator and the templates map them to catalog exercises. They carry no medical detail,
/// so they are safe to pass to the language model.
public enum MovementTag: String, Codable, Sendable, CaseIterable {
    case jumps, deepLunges, overheadPress, barbellDeadlift, deepSquats, loadedPushups

    /// Polish name shown to the user ("Pomijamy: ...").
    public var displayName: String {
        switch self {
        case .jumps: return "skoki"
        case .deepLunges: return "głębokie wykroki"
        case .overheadPress: return "wyciskanie nad głowę"
        case .barbellDeadlift: return "martwy ciąg ze sztangą"
        case .deepSquats: return "głębokie przysiady"
        case .loadedPushups: return "pompki z obciążeniem"
        }
    }
}

public struct UserProfile: Codable, Equatable, Sendable {
    public var goal: TrainingGoal
    public var level: TrainingLevel
    /// 2...5
    public var daysPerWeek: Int
    public var sessionMinutes: Int
    public var equipment: Equipment
    /// Free text from the user ("czego unikać"). We do not judge it medically.
    public var avoid: String
    /// Everything the user ticked in onboarding. `equipment` is derived from it.
    public var gear: [GearItem]
    /// Movements to leave out of the plan (derived from onboarding, no medical detail).
    public var avoidTags: [MovementTag]
    /// Plan the first weeks lighter (fewer sets). Set when onboarding suggests caution.
    public var easyStart: Bool

    public init(goal: TrainingGoal, level: TrainingLevel, daysPerWeek: Int, sessionMinutes: Int,
                equipment: Equipment, avoid: String = "", gear: [GearItem] = [],
                avoidTags: [MovementTag] = [], easyStart: Bool = false) {
        self.goal = goal
        self.level = level
        self.daysPerWeek = daysPerWeek
        self.sessionMinutes = sessionMinutes
        self.equipment = equipment
        self.avoid = avoid
        self.gear = gear
        self.avoidTags = avoidTags
        self.easyStart = easyStart
    }

    // Profiles saved before the newer fields existed still decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        goal = try c.decode(TrainingGoal.self, forKey: .goal)
        level = try c.decode(TrainingLevel.self, forKey: .level)
        daysPerWeek = try c.decode(Int.self, forKey: .daysPerWeek)
        sessionMinutes = try c.decode(Int.self, forKey: .sessionMinutes)
        equipment = try c.decode(Equipment.self, forKey: .equipment)
        avoid = try c.decodeIfPresent(String.self, forKey: .avoid) ?? ""
        gear = try c.decodeIfPresent([GearItem].self, forKey: .gear) ?? []
        avoidTags = try c.decodeIfPresent([MovementTag].self, forKey: .avoidTags) ?? []
        easyStart = try c.decodeIfPresent(Bool.self, forKey: .easyStart) ?? false
    }
}

/// An item in the exercise catalog. Plan and coach may use only catalog ids.
public struct ExerciseItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var muscleGroup: String
    public var equipment: Equipment
    public var level: TrainingLevel
    public var summary: String
    public var videoURL: URL?
    public var substituteIds: [String]
    /// True when the app can analyse technique for this exercise (demo: only the squat).
    public var supportsAnalysis: Bool
    /// Tempo used by the live coach and by the plan generator when nothing else is set.
    public var defaultTempo: TempoSpec?
    /// True when "reps" of this exercise are seconds (plank, marching). Absent in older catalogs.
    public var timed: Bool?
    /// Movement pattern from the catalog (squat, hinge, lunge, push, pull, core, cardio). Absent in older catalogs.
    public var pattern: String?
    /// Movements this exercise contains, matched against `UserProfile.avoidTags` (e.g. a lunge has `deepLunges`).
    /// Absent in older catalogs and in sample data.
    public var movementTags: [MovementTag]?

    public init(id: String, name: String, muscleGroup: String, equipment: Equipment, level: TrainingLevel,
                summary: String, videoURL: URL? = nil, substituteIds: [String] = [],
                supportsAnalysis: Bool = false, defaultTempo: TempoSpec? = nil, timed: Bool? = nil, pattern: String? = nil,
                movementTags: [MovementTag]? = nil) {
        self.timed = timed
        self.pattern = pattern
        self.movementTags = movementTags
        self.id = id
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.level = level
        self.summary = summary
        self.videoURL = videoURL
        self.substituteIds = substituteIds
        self.supportsAnalysis = supportsAnalysis
        self.defaultTempo = defaultTempo
    }
}

public struct PlannedExercise: Codable, Equatable, Sendable, Identifiable {
    public var id: String { exerciseId }
    public var exerciseId: String
    public var sets: Int
    public var repsMin: Int
    public var repsMax: Int
    public var restSeconds: Int
    /// Target tempo for the live coach. nil = no tempo coaching for this exercise.
    public var tempo: TempoSpec?

    public init(exerciseId: String, sets: Int, repsMin: Int, repsMax: Int, restSeconds: Int,
                tempo: TempoSpec? = nil) {
        self.exerciseId = exerciseId
        self.sets = sets
        self.repsMin = repsMin
        self.repsMax = repsMax
        self.restSeconds = restSeconds
        self.tempo = tempo
    }
}

public enum SessionStatus: String, Codable, Sendable {
    case planned, done, adapted
}

public struct PlannedSession: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// 1 = Monday ... 7 = Sunday. For a session with a `date` it is the weekday of that date.
    public var weekday: Int
    /// The calendar day of the session (start of that day, local time). Nil in a plain weekly pattern, which is what
    /// the backend and the templates produce; the app turns it into dated sessions (`Plan.PlanScheduler`).
    public var date: Date?
    public var title: String
    public var exercises: [PlannedExercise]
    public var status: SessionStatus
    /// Why the session was changed (shown to the user), e.g. "Lżejszy trening: krótki sen, niższe HRV".
    public var adaptationNote: String?

    public init(id: UUID = UUID(), weekday: Int, title: String, exercises: [PlannedExercise],
                status: SessionStatus = .planned, adaptationNote: String? = nil, date: Date? = nil) {
        self.id = id
        self.weekday = weekday
        self.date = date
        self.title = title
        self.exercises = exercises
        self.status = status
        self.adaptationNote = adaptationNote
    }
}

public enum PlanSource: String, Codable, Sendable {
    case ai, template
}

/// Why a plan is not the plain plan from the AI. The plan generator sets them and the screens show the first one,
/// so the user is never left wondering why the plan came from a template.
public enum PlanNotice: String, Codable, Sendable, Equatable {
    /// The AI did not answer in time or the server had a problem: the plan comes from the server's template.
    case aiUnavailable
    /// The AI proposed a plan that failed the checks (unknown exercise, missing equipment, ...).
    case aiInvalidPlan
    /// No connection to the server: the plan was built on the phone from the bundled template.
    case offline
    /// The free text "czego unikać" cannot be read by a template; only the ticked movements were left out.
    case avoidTextNotApplied

    /// Polish text for the user.
    public var userMessage: String {
        switch self {
        case .aiUnavailable: return "Trener AI był niedostępny, więc plan pochodzi z gotowego szablonu."
        case .aiInvalidPlan: return "Plan od trenera AI nie przeszedł sprawdzenia, więc użyłem planu z szablonu."
        case .offline: return "Brak połączenia z serwerem. Plan ułożyłem na telefonie z szablonu, możesz go później ułożyć od nowa."
        case .avoidTextNotApplied: return "Szablon nie czyta wpisanego tekstu „czego unikać”. Pominąłem tylko zaznaczone ruchy."
        }
    }
}

public struct TrainingPlan: Codable, Equatable, Sendable {
    public var createdAt: Date
    public var source: PlanSource
    /// With dates, every session of the whole plan (a few weeks); without, one weekly pattern.
    public var sessions: [PlannedSession]
    /// Notes on how this plan came to be (empty for a normal plan). Absent in plans saved by older versions.
    public var notices: [PlanNotice]
    /// First day of a dated plan (start of that day) and how many weeks it runs from there. Nil for a weekly pattern.
    public var startDate: Date?
    public var weeks: Int?

    public init(createdAt: Date, source: PlanSource, sessions: [PlannedSession], notices: [PlanNotice] = [],
                startDate: Date? = nil, weeks: Int? = nil) {
        self.createdAt = createdAt
        self.source = source
        self.sessions = sessions
        self.notices = notices
        self.startDate = startDate
        self.weeks = weeks
    }

    private enum CodingKeys: String, CodingKey { case createdAt, source, sessions, notices, startDate, weeks }

    // Plans saved before `notices` existed still decode; a notice this version does not know is dropped.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        source = try c.decode(PlanSource.self, forKey: .source)
        sessions = try c.decode([PlannedSession].self, forKey: .sessions)
        notices = (try c.decodeIfPresent([String].self, forKey: .notices) ?? []).compactMap(PlanNotice.init(rawValue:))
        startDate = try c.decodeIfPresent(Date.self, forKey: .startDate)
        weeks = try c.decodeIfPresent(Int.self, forKey: .weeks)
    }
}
