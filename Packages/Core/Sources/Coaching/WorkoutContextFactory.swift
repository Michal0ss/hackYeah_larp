import Contracts
import Foundation
import Plan

/// The context sent with a question asked in the middle of a workout: where the user is and what the last set was.
/// Numbers only (no poses, no video, no pain or effort).
public enum WorkoutContextFactory {
    /// - Parameters:
    ///   - screen: where the question is asked from (`rest` and `setSummary` after a set, `liveSet` during one).
    ///   - liveSummary: the result of the last set when the live coach counted it (technique and tempo).
    public static func context(for run: WorkoutRun, screen: WorkoutScreen, liveSummary: SetSummary? = nil) -> WorkoutContext {
        var context = WorkoutContext(screen: screen, sessionId: run.session.id, exerciseId: run.currentExercise?.exerciseId,
                                     setIndex: run.setIndex, totalSets: run.setsInCurrentExercise > 0 ? run.setsInCurrentExercise : nil)
        guard screen != .liveSet, let last = run.lastSet else { return context }
        context.exerciseId = last.exerciseId
        context.setIndex = last.setIndex
        context.totalSets = run.session.exercises.first { $0.exerciseId == last.exerciseId }?.sets

        // What the camera measured travels as the set digest; what the user typed or corrected, as the logged set.
        if last.source == .live, let liveSummary, last.liveSetId == liveSummary.id {
            context.lastSet = SetDigest(liveSummary)
        }
        if last.source == .manual || last.isEdited || last.weightKg != nil || context.lastSet == nil {
            let planned = run.session.exercises.first { $0.exerciseId == last.exerciseId }
            context.loggedSet = LoggedSetDigest(setIndex: last.setIndex, reps: last.reps, seconds: last.seconds,
                                                weightKg: last.weightKg, plannedMin: planned?.repsMin,
                                                plannedMax: planned?.repsMax)
        }
        return context
    }
}
