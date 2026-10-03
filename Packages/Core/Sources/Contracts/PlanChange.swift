import Foundation

// A change of the plan that the coach PROPOSES in a conversation. The model never changes the plan: the app shows a
// card, and the plan changes only after the user taps "Zastosuj". Logic: `Plan.PlanChanger`; tool: `Coaching`.

public enum PlanChangeKind: String, Codable, Sendable, CaseIterable {
    /// Replace one exercise of a session with another one from the catalog.
    case swapExercise
    /// One set less in every exercise that has more than two.
    case lighterSession
    /// Move a session to a weekday without a session.
    case moveSession
    /// Leave a session out (it stays in the plan as skipped and can be put back).
    case skipSession
    /// Add an exercise from the catalog to a session.
    case addExercise
    /// Take an exercise out of a session (a session keeps at least one).
    case removeExercise
    /// Change the sets, the reps (or seconds) and the rest of one exercise.
    case editExercise
}

public enum PlanChangeStatus: String, Codable, Sendable {
    case pending, applied, dismissed, undone
}

public struct PlanChangeProposal: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: PlanChangeKind
    public var status: PlanChangeStatus
    /// `PlannedSession.id` the change concerns.
    public var sessionId: UUID
    public var sessionTitle: String
    /// 1 = Monday ... 7 = Sunday: where the session is when proposed.
    public var weekday: Int
    /// `swapExercise`: the exercise to replace and its replacement (catalog ids).
    public var exerciseId: String?
    public var replacementExerciseId: String?
    /// `moveSession`: the weekday to move to.
    public var newWeekday: Int?
    /// `addExercise` / `removeExercise` / `editExercise`: the exercise the change is about (`exerciseId`), and for
    /// `addExercise` / `editExercise` the numbers asked for (nil = the usual for a new exercise, unchanged for an edit).
    public var sets: Int?
    public var repsMin: Int?
    public var repsMax: Int?
    public var restSeconds: Int?
    /// Polish description of the change, written by the app (the model's words are never shown as the change).
    public var summary: String
    /// One sentence from the coach about why. Data from the model: shown as a quote, never acted on.
    public var reason: String?
    /// The session before the change and right after it, kept so that the change can be undone safely.
    public var before: PlannedSession?
    public var after: PlannedSession?

    public init(id: UUID = UUID(), kind: PlanChangeKind, status: PlanChangeStatus = .pending, sessionId: UUID,
                sessionTitle: String, weekday: Int, exerciseId: String? = nil, replacementExerciseId: String? = nil,
                newWeekday: Int? = nil, summary: String, reason: String? = nil, before: PlannedSession? = nil,
                after: PlannedSession? = nil, sets: Int? = nil, repsMin: Int? = nil, repsMax: Int? = nil,
                restSeconds: Int? = nil) {
        self.id = id
        self.kind = kind
        self.status = status
        self.sessionId = sessionId
        self.sessionTitle = sessionTitle
        self.weekday = weekday
        self.exerciseId = exerciseId
        self.replacementExerciseId = replacementExerciseId
        self.newWeekday = newWeekday
        self.sets = sets
        self.repsMin = repsMin
        self.repsMax = repsMax
        self.restSeconds = restSeconds
        self.summary = summary
        self.reason = reason
        self.before = before
        self.after = after
    }
}
