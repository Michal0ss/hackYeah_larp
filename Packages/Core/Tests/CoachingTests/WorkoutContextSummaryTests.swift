import Contracts
import XCTest
@testable import Coaching

final class WorkoutContextSummaryTests: XCTestCase {
    func testBeforeTheWorkoutTheSummaryNamesTheSession() {
        let summary = WorkoutContextSummary.make(for: WorkoutContext(screen: .plan), sessionTitle: "Całe ciało A", exerciseName: nil)
        XCTAssertEqual(summary.title, "Pytasz przed treningiem")
        XCTAssertEqual(summary.lines, ["Trening: Całe ciało A"])
    }

    func testDuringASetItNamesTheExerciseAndTheSet() {
        let context = WorkoutContext(screen: .liveSet, exerciseId: "squat", setIndex: 2, totalSets: 3)
        let summary = WorkoutContextSummary.make(for: context, sessionTitle: "Nogi", exerciseName: "Przysiad")
        XCTAssertEqual(summary.lines, ["Trening: Nogi", "Ćwiczenie: Przysiad · seria 2 z 3"])
    }

    func testAfterASetItShowsWhatTheCameraMeasured() {
        let digest = SetDigest(setIndex: 1, reps: 6, fullRangeReps: 5, techniqueScore: 82, tempoScore: 70, targetTempo: "3-1-2-0",
                               averageDescentSeconds: 2.5, averageAscentSeconds: 1.5, framing: .good, findings: [])
        let summary = WorkoutContextSummary.make(for: WorkoutContext(screen: .setSummary, lastSet: digest), sessionTitle: nil, exerciseName: nil)
        XCTAssertEqual(summary.lines, ["Ostatnia seria: 6 powt., technika 82/100, tempo 70/100"])
    }

    func testATypedSetShowsRepsAndWeight() {
        let logged = LoggedSetDigest(setIndex: 1, reps: 8, weightKg: 17.5)
        let summary = WorkoutContextSummary.make(for: WorkoutContext(screen: .rest, loggedSet: logged), sessionTitle: nil, exerciseName: nil)
        XCTAssertEqual(summary.lines, ["Ostatnia seria: 8 powt., 17,5 kg"])
    }

    func testEveryScreenHasATitle() {
        for screen in WorkoutScreen.allCases {
            XCTAssertFalse(WorkoutContextSummary.make(for: WorkoutContext(screen: screen), sessionTitle: nil, exerciseName: nil).title.isEmpty)
        }
    }
}
