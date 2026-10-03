import Contracts
import Foundation

/// Rest between sets. It stores the moment it ends, not a counter, so it stays right when the screen is locked, the
/// app is in the background or a sheet (the coach) covers it.
public struct RestTimer: Equatable, Sendable {
    public static let step = 15
    public static let maxSeconds = 600

    public private(set) var endsAt: Date
    /// Length of the rest at its start plus what was added, for the ring.
    public private(set) var totalSeconds: Int

    public init(seconds: Int, now: Date = Date()) {
        let clamped = min(max(seconds, 0), Self.maxSeconds)
        totalSeconds = clamped
        endsAt = now.addingTimeInterval(TimeInterval(clamped))
    }

    /// Seconds left, never below 0.
    public func remaining(at now: Date) -> TimeInterval { max(0, endsAt.timeIntervalSince(now)) }

    public func isFinished(at now: Date) -> Bool { remaining(at: now) <= 0 }

    /// 0 at the start, 1 when the rest is over.
    public func progress(at now: Date) -> Double {
        totalSeconds == 0 ? 1 : min(1, max(0, 1 - remaining(at: now) / Double(totalSeconds)))
    }

    /// Longer or shorter by `seconds` (±15 on the screen). It cannot go below zero or above ten minutes in total.
    public mutating func add(_ seconds: Int, now: Date) {
        let left = remaining(at: now)
        let newLeft = min(max(left + TimeInterval(seconds), 0), TimeInterval(Self.maxSeconds))
        endsAt = now.addingTimeInterval(newLeft)
        totalSeconds = min(max(totalSeconds + Int(newLeft - left), 0), Self.maxSeconds)
    }

    public mutating func skip(now: Date) { endsAt = now }
}

/// What comes after the set that was just done.
public enum WorkoutUpcoming: Equatable, Sendable {
    case set(number: Int, of: Int)
    case exercise(PlannedExercise)
    case finished
}

/// Where the user is in a session from the plan: which exercise and set, what was done, the rest timer. Pure and
/// deterministic (time is passed in), so the whole flow is tested without a screen.
///
///     overview ──begin──► performing ──complete(set)──► resting ──next──► performing (next set or exercise) ...
///                                                          └─ the last set ──next──► finished
///
/// The session passed in is the one the user sees (already adjusted for today), so its sets are the ones to do.
public struct WorkoutRun: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case overview, performing, resting, finished
    }

    public let session: PlannedSession
    public private(set) var phase: Phase = .overview
    /// Index in `session.exercises`.
    public private(set) var exerciseIndex = 0
    /// 1-based number of the set being done, or just done while resting.
    public private(set) var setIndex = 1
    public private(set) var skippedExercises: Set<Int> = []
    /// The sets done in this run, in the order they were done.
    public private(set) var sets: [LoggedSet] = []
    /// Only while resting, and not after the very last set.
    public private(set) var rest: RestTimer?

    public init(session: PlannedSession) {
        self.session = session
    }

    // MARK: reading

    public var currentExercise: PlannedExercise? {
        session.exercises.indices.contains(exerciseIndex) ? session.exercises[exerciseIndex] : nil
    }

    /// Sets planned for the current exercise.
    public var setsInCurrentExercise: Int { currentExercise?.sets ?? 0 }

    public var lastSet: LoggedSet? { sets.last }

    public var completedSets: Int { sets.count }

    /// Sets to do: all sets of the exercises that are not skipped, and for a skipped one only the sets already done
    /// (so a half-done exercise that was left out does not count as a missed one).
    public var plannedSets: Int {
        session.exercises.indices.map { index in
            skippedExercises.contains(index) ? sets(of: session.exercises[index].exerciseId).count : session.exercises[index].sets
        }.reduce(0, +)
    }

    /// What is next, looking from the current position.
    public var upcoming: WorkoutUpcoming {
        if setIndex < setsInCurrentExercise, !skippedExercises.contains(exerciseIndex) {
            return .set(number: setIndex + 1, of: setsInCurrentExercise)
        }
        if let next = nextExerciseIndex { return .exercise(session.exercises[next]) }
        return .finished
    }

    private var nextExerciseIndex: Int? {
        session.exercises.indices.first { $0 > exerciseIndex && !skippedExercises.contains($0) }
    }

    /// Sets done for one exercise of the session.
    public func sets(of exerciseId: String) -> [LoggedSet] { sets.filter { $0.exerciseId == exerciseId } }

    // MARK: moving

    /// Starts the first exercise, or `exercise` (the user tapped "zacznij od tego").
    public mutating func begin(atExercise exercise: Int = 0) {
        guard phase == .overview, session.exercises.indices.contains(exercise) else { return }
        exerciseIndex = exercise
        // Exercises before the chosen one are left out.
        skippedExercises = Set(0..<exercise)
        setIndex = 1
        phase = .performing
    }

    /// The set was done: it is recorded and the rest starts.
    public mutating func complete(_ set: LoggedSet, now: Date = Date()) {
        guard phase == .performing else { return }
        record(set)
        phase = .resting
        let isEnd = upcoming == .finished
        rest = isEnd ? nil : RestTimer(seconds: currentExercise?.restSeconds ?? 0, now: now)
    }

    /// New numbers for a set of this run (the user corrected them).
    public mutating func update(_ set: LoggedSet) {
        if let index = sets.firstIndex(where: { $0.id == set.id }) { sets[index] = set }
    }

    /// Leaves the rest and goes to the next set, the next exercise, or the end.
    public mutating func next() {
        guard phase == .resting else { return }
        rest = nil
        switch upcoming {
        case .set(let number, _):
            setIndex = number
            phase = .performing
        case .exercise:
            moveToNextExercise()
        case .finished:
            phase = .finished
        }
    }

    /// Leaves out the rest of the current exercise (sets already done stay).
    public mutating func skipExercise() {
        guard phase == .performing || phase == .resting else { return }
        skippedExercises.insert(exerciseIndex)
        rest = nil
        if nextExerciseIndex == nil { phase = .finished } else { moveToNextExercise() }
    }

    /// Ends the session where it is.
    public mutating func finish() {
        guard phase != .finished else { return }
        rest = nil
        phase = .finished
    }

    // MARK: rest timer

    public mutating func extendRest(by seconds: Int, now: Date = Date()) {
        rest?.add(seconds, now: now)
    }

    public mutating func skipRest(now: Date = Date()) {
        rest?.skip(now: now)
    }

    // MARK: private

    private mutating func moveToNextExercise() {
        guard let next = nextExerciseIndex else {
            phase = .finished
            return
        }
        exerciseIndex = next
        setIndex = 1
        phase = .performing
    }

    private mutating func record(_ set: LoggedSet) {
        sets.removeAll { $0.id == set.id || ($0.exerciseId == set.exerciseId && $0.setIndex == set.setIndex) }
        sets.append(set)
    }
}
