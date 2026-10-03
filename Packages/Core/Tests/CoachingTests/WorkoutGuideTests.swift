import Contracts
import XCTest
@testable import Coaching

final class WorkoutGuideTests: XCTestCase {
    private let squat = WorkoutGuide.Entry(
        name: "Przysiad", planned: PlannedExercise(exerciseId: "squat", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 90,
                                                   tempo: .controlled), live: true)
    private let plank = WorkoutGuide.Entry(
        name: "Plank", planned: PlannedExercise(exerciseId: "plank", sets: 2, repsMin: 30, repsMax: 30, restSeconds: 60),
        timed: true)

    func testSessionQuestionListsEveryExerciseInOrderWithItsNumbers() {
        let text = WorkoutGuide.sessionQuestion(title: "Nogi", entries: [squat, plank])
        XCTAssertTrue(text.contains("1. Przysiad: 3 × 8–10 powt., przerwa 90 s, tempo 3-1-2-0"), text)
        XCTAssertTrue(text.contains("2. Plank: 2 × 30 s, przerwa 60 s"), text)
        XCTAssertFalse(text.contains("2. Plank: 2 × 30 s, przerwa 60 s, tempo"), text)
        XCTAssertLessThan(text.range(of: "Przysiad:")!.lowerBound, text.range(of: "Plank:")!.lowerBound)
    }

    func testExerciseQuestionHasTheNumbersOfThePlan() {
        let text = WorkoutGuide.exerciseQuestion(squat)
        XCTAssertTrue(text.contains("„Przysiad”"))
        XCTAssertTrue(text.contains("3 × 8–10 powt."))
        XCTAssertTrue(text.contains("tempo 3-1-2-0"))
    }

    func testQuestionsFitTheServerLimit() {
        let many = Array(repeating: squat, count: 12)
        XCTAssertLessThanOrEqual(WorkoutGuide.sessionQuestion(title: "Długi trening", entries: many).count, CoachChat.maxTextCharacters)
    }

    func testFractionalTempoUsesAComma() {
        XCTAssertEqual(WorkoutGuide.tempoText(TempoSpec(eccentric: 2.5, bottomPause: 0, concentric: 1, topPause: 0)), "2,5-0-1-0")
    }
}
