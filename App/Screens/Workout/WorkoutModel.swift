import Contracts
import Coaching
import Foundation
import LiveSet
import Observation
import Plan

/// A workout from the plan in progress: the state machine (`WorkoutRun`), and what happens to the numbers on the way.
/// Every set is written to the training log the moment it is done, so leaving in the middle loses nothing.
@MainActor
@Observable
final class WorkoutModel {
    private(set) var run: WorkoutRun
    /// What the camera measured for the sets done with the live coach, by `LoggedSet.liveSetId`.
    private(set) var liveSummaries: [UUID: SetSummary] = [:]
    /// Set once the workout is saved (the session is marked as done).
    private(set) var saved = false

    /// Exercises the user chose to do without the camera: they are typed in like the rest.
    private(set) var videoSkipped: Set<String> = []

    private let store: AppStore
    private let startExercise: Int

    init(session: PlannedSession, store: AppStore, startExercise: Int = 0) {
        run = WorkoutRun(session: session)
        self.store = store
        self.startExercise = startExercise
    }

    var session: PlannedSession { run.session }
    private var log: TrainingLogStore { store.services.trainingLog }

    func exercise(_ planned: PlannedExercise) -> ExerciseItem? { store.exercise(id: planned.exerciseId) }

    /// Exercises with a target tempo that the live coach can follow go through the camera; the rest are typed in.
    func isLive(_ planned: PlannedExercise) -> Bool {
        canAnalyse(planned) && !videoSkipped.contains(planned.exerciseId)
    }

    /// The camera could follow this exercise (a target tempo and a movement the live coach knows).
    func canAnalyse(_ planned: PlannedExercise) -> Bool {
        guard planned.tempo != nil, let exercise = exercise(planned) else { return false }
        return MovementKind.kind(for: exercise) != nil
    }

    /// Every exercise of the workout the camera could follow is already skipped.
    var allVideoSkipped: Bool { session.exercises.allSatisfy { !canAnalyse($0) || videoSkipped.contains($0.exerciseId) } }

    func skipVideo(_ planned: PlannedExercise) { videoSkipped.insert(planned.exerciseId) }

    /// The overview button: no camera for the whole workout (or back to the camera).
    func setVideoSkippedForAll(_ skipped: Bool) {
        videoSkipped = skipped ? Set(session.exercises.filter(canAnalyse).map(\.exerciseId)) : []
    }

    func isTimed(_ planned: PlannedExercise) -> Bool { exercise(planned)?.timed ?? false }

    /// The weight used last time, to start from.
    func lastWeight(_ exerciseId: String) -> Double? { log.lastWeight(exerciseId: exerciseId) }

    // MARK: moving

    func begin() { run.begin(atExercise: startExercise) }

    /// The live coach finished a set: the camera result is kept (technique history) and the set logged.
    func completeLive(_ summary: SetSummary) {
        guard run.phase == .performing, let planned = run.currentExercise else { return }
        liveSummaries[summary.id] = summary
        store.recordSet(summary)
        let set = LoggedSet(sessionId: session.id, exerciseId: planned.exerciseId, setIndex: run.setIndex,
                            reps: summary.reps.count, source: .live, liveSetId: summary.id)
        finish(set)
    }

    /// A set typed in (an exercise without live analysis).
    func completeManual(reps: Int?, seconds: Int?, weightKg: Double?) {
        guard run.phase == .performing, let planned = run.currentExercise else { return }
        finish(LoggedSet(sessionId: session.id, exerciseId: planned.exerciseId, setIndex: run.setIndex, reps: reps,
                         seconds: seconds, weightKg: weightKg, source: .manual))
    }

    private func finish(_ set: LoggedSet) {
        log.record(set)
        run.complete(set)
    }

    /// The user corrected the numbers of a set (reps, seconds or weight).
    func edit(_ set: LoggedSet, reps: Int?, seconds: Int?, weightKg: Double?) {
        // `weightKg: .some(nil)` takes the weight away.
        guard let changed = log.edit(set.id, reps: reps, seconds: seconds, weightKg: .some(weightKg)) else { return }
        run.update(changed)
    }

    func next() { run.next() }
    func skipExercise() { run.skipExercise() }
    func extendRest(_ seconds: Int) { run.extendRest(by: seconds) }
    func skipRest() { run.skipRest() }
    func endEarly() { run.finish() }

    /// "Zapisz i zakończ": the session counts as done when at least one set was done.
    func save(feedback: SessionFeedback? = nil) {
        guard !saved else { return }
        saved = true
        guard run.completedSets > 0 else { return }
        if let feedback {
            let feedbackStore = store.services.sessionFeedback
            Task { await feedbackStore.save(feedback) }
        }
        store.services.planStore.recordCompletion(sessionId: session.id, completedSets: run.completedSets,
                                                  plannedSets: run.plannedSets)
        Task { await store.refreshRecommendation() }
        store.dataChanged()
    }

    // MARK: totals for the end screen

    struct ExerciseResult: Identifiable {
        var id: String { planned.exerciseId }
        let planned: PlannedExercise
        let sets: [LoggedSet]
        let skipped: Bool
    }

    var results: [ExerciseResult] {
        session.exercises.enumerated().map { index, planned in
            ExerciseResult(planned: planned, sets: run.sets(of: planned.exerciseId), skipped: run.skippedExercises.contains(index))
        }
    }

    var totalReps: Int { run.sets.compactMap(\.reps).reduce(0, +) }

    // MARK: the coach

    /// The exercises still to do (from the one the workout starts at) as the guide describes them.
    private func guideEntry(_ planned: PlannedExercise) -> WorkoutGuide.Entry {
        WorkoutGuide.Entry(name: exercise(planned)?.name ?? planned.exerciseId, planned: planned,
                           timed: isTimed(planned), live: isLive(planned))
    }

    /// "Przeprowadź mnie przez trening": the whole session as one question to the coach.
    var guideQuestion: String {
        WorkoutGuide.sessionQuestion(title: session.title,
                                     entries: session.exercises.dropFirst(startExercise).map(guideEntry))
    }

    /// "Wytłumacz to ćwiczenie": the exercise being done.
    var explainQuestion: String? {
        run.currentExercise.map { WorkoutGuide.exerciseQuestion(guideEntry($0)) }
    }

    /// What the coach is told when asked from the screen the user is on.
    func coachContext(screen: WorkoutScreen) -> WorkoutContext {
        let last = run.lastSet.flatMap { $0.liveSetId }.flatMap { liveSummaries[$0] }
        return WorkoutContextFactory.context(for: run, screen: screen, liveSummary: last)
    }
}
