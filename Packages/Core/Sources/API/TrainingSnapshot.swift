import Contracts
import Foundation

// What the coach is told about the user's training in every request, so that simple questions ("co dziś trenuję?",
// "jak poprawić technikę?") are answered at once instead of after a round trip through the tools.
//
// Only training data: the plan and the last technique result as numbers. Ids instead of names (the server knows the
// catalog), no poses, no video, no free text typed by the user. What is derived from health signals (a session that
// was lightened for today and the reason) is sent only with the user's consent.

public struct ExerciseDigest: Codable, Equatable, Sendable {
    public var exerciseId: String
    public var sets: Int
    public var repsMin: Int
    public var repsMax: Int
    public var restSeconds: Int
    /// Written like "3-1-2-0".
    public var tempo: String?

    public init(exerciseId: String, sets: Int, repsMin: Int, repsMax: Int, restSeconds: Int, tempo: String? = nil) {
        self.exerciseId = exerciseId
        self.sets = sets
        self.repsMin = repsMin
        self.repsMax = repsMax
        self.restSeconds = restSeconds
        self.tempo = tempo
    }

    public init(_ planned: PlannedExercise) {
        self.init(exerciseId: planned.exerciseId, sets: planned.sets, repsMin: planned.repsMin, repsMax: planned.repsMax,
                  restSeconds: planned.restSeconds, tempo: planned.tempo?.label)
    }
}

public struct SessionDigest: Codable, Equatable, Sendable {
    /// 1 = Monday ... 7 = Sunday.
    public var weekday: Int
    /// The day of the session as `2026-10-14` (the user's calendar). Nil for a plan without dates.
    public var date: String?
    public var title: String
    public var status: SessionStatus
    /// Why the session was changed. Built from health signals, so only with consent.
    public var adaptationNote: String?
    public var exercises: [ExerciseDigest]

    public init(weekday: Int, title: String, status: SessionStatus, adaptationNote: String? = nil,
                exercises: [ExerciseDigest], date: String? = nil) {
        self.weekday = weekday
        self.date = date
        self.title = title
        self.status = status
        self.adaptationNote = adaptationNote
        self.exercises = exercises
    }
}

/// The latest technique analysis: score and the main findings.
public struct TechniqueDigest: Codable, Equatable, Sendable {
    public static let maxFindings = 4

    public var exerciseId: String
    public var daysAgo: Int
    public var score: Int
    public var findings: [FindingDigest]
    public var substituteExerciseId: String?
    public var isSimulated: Bool

    public init(exerciseId: String, daysAgo: Int, score: Int, findings: [FindingDigest],
                substituteExerciseId: String? = nil, isSimulated: Bool = false) {
        self.exerciseId = exerciseId
        self.daysAgo = daysAgo
        self.score = score
        self.findings = findings
        self.substituteExerciseId = substituteExerciseId
        self.isSimulated = isSimulated
    }
}

public struct TrainingSnapshot: Codable, Equatable, Sendable {
    /// ISO weekday of the request (1 = Monday).
    public var today: Int
    /// Today as `2026-10-14` (the user's calendar): the model has no clock, and dates in the plan need it.
    public var todayDate: String?
    public var planSource: PlanSource?
    /// Today's session, or the next planned one when `nextSessionIsToday` is false.
    public var nextSession: SessionDigest?
    public var nextSessionIsToday: Bool
    public var week: [SessionDigest]
    public var lastTechnique: TechniqueDigest?

    public init(today: Int, planSource: PlanSource? = nil, nextSession: SessionDigest? = nil,
                nextSessionIsToday: Bool = true, week: [SessionDigest] = [], lastTechnique: TechniqueDigest? = nil,
                todayDate: String? = nil) {
        self.today = today
        self.todayDate = todayDate
        self.planSource = planSource
        self.nextSession = nextSession
        self.nextSessionIsToday = nextSessionIsToday
        self.week = week
        self.lastTechnique = lastTechnique
    }

    /// True when any of the data in it is sample data (the answer is then marked "Dane przykładowe").
    public var containsSampleData: Bool { lastTechnique?.isSimulated ?? false }
}
