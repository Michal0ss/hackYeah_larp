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

public struct UserProfile: Codable, Equatable, Sendable {
    public var goal: TrainingGoal
    public var level: TrainingLevel
    /// 2...5
    public var daysPerWeek: Int
    public var sessionMinutes: Int
    public var equipment: Equipment
    /// Free text from the user ("czego unikać"). We do not judge it medically.
    public var avoid: String

    public init(goal: TrainingGoal, level: TrainingLevel, daysPerWeek: Int, sessionMinutes: Int,
                equipment: Equipment, avoid: String = "") {
        self.goal = goal
        self.level = level
        self.daysPerWeek = daysPerWeek
        self.sessionMinutes = sessionMinutes
        self.equipment = equipment
        self.avoid = avoid
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

    public init(id: String, name: String, muscleGroup: String, equipment: Equipment, level: TrainingLevel,
                summary: String, videoURL: URL? = nil, substituteIds: [String] = [],
                supportsAnalysis: Bool = false, defaultTempo: TempoSpec? = nil) {
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
    /// 1 = Monday ... 7 = Sunday.
    public var weekday: Int
    public var title: String
    public var exercises: [PlannedExercise]
    public var status: SessionStatus
    /// Why the session was changed (shown to the user), e.g. "Lżejszy trening: krótki sen, niższe HRV".
    public var adaptationNote: String?

    public init(id: UUID = UUID(), weekday: Int, title: String, exercises: [PlannedExercise],
                status: SessionStatus = .planned, adaptationNote: String? = nil) {
        self.id = id
        self.weekday = weekday
        self.title = title
        self.exercises = exercises
        self.status = status
        self.adaptationNote = adaptationNote
    }
}

public enum PlanSource: String, Codable, Sendable {
    case ai, template
}

public struct TrainingPlan: Codable, Equatable, Sendable {
    public var createdAt: Date
    public var source: PlanSource
    public var sessions: [PlannedSession]

    public init(createdAt: Date, source: PlanSource, sessions: [PlannedSession]) {
        self.createdAt = createdAt
        self.source = source
        self.sessions = sessions
    }
}
