import Contracts
import XCTest
@testable import Coaching

final class QuickQuestionsTests: XCTestCase {
    private func set(technique: Int?, findings: [FindingDigest] = []) -> SetDigest {
        SetDigest(setIndex: 2, reps: 6, fullRangeReps: 4, techniqueScore: technique, tempoScore: 60, targetTempo: "3-1-2-0",
                  averageDescentSeconds: 1.6, averageAscentSeconds: 1.1, framing: .good, findings: findings)
    }

    func testOutsideAWorkoutTheGeneralQuestionsAreOffered() {
        XCTAssertEqual(CoachChat.quickQuestions(for: nil), CoachChat.starterQuestions)
        XCTAssertEqual(CoachChat.quickQuestions(for: WorkoutContext(screen: .plan)), CoachChat.starterQuestions)
    }

    func testEveryScreenHasQuestionsAndNoDuplicates() {
        for screen in WorkoutScreen.allCases {
            let questions = CoachChat.quickQuestions(for: WorkoutContext(screen: screen, setIndex: 1, totalSets: 3))
            XCTAssertFalse(questions.isEmpty, "\(screen)")
            XCTAssertEqual(Set(questions).count, questions.count, "\(screen)")
            XCTAssertLessThanOrEqual(questions.count, 4)
        }
    }

    func testAfterASetTheQuestionsFollowTheResult() {
        let weak = WorkoutContext(screen: .setSummary, lastSet: set(technique: 64, findings: [
            FindingDigest(id: "depth_shallow", title: "Zbyt płytko", severity: .major, repsAffected: 2, repsTotal: 6)]))
        let strong = WorkoutContext(screen: .setSummary, lastSet: set(technique: 91))
        let weakQuestions = CoachChat.quickQuestions(for: weak)
        XCTAssertTrue(weakQuestions.contains("Dlaczego ta uwaga?"))
        XCTAssertTrue(weakQuestions.contains("Zamień to ćwiczenie na łatwiejsze"))
        XCTAssertFalse(weakQuestions.contains("Czy mogę dołożyć ciężar?"))
        let strongQuestions = CoachChat.quickQuestions(for: strong)
        XCTAssertTrue(strongQuestions.contains("Czy mogę dołożyć ciężar?"))
        XCTAssertFalse(strongQuestions.contains("Dlaczego ta uwaga?"))
    }

    func testAnotherSetIsOfferedOnlyWhenThereIsOneLeft() {
        let middle = CoachChat.quickQuestions(for: WorkoutContext(screen: .rest, setIndex: 2, totalSets: 4))
        let end = CoachChat.quickQuestions(for: WorkoutContext(screen: .rest, setIndex: 4, totalSets: 4))
        XCTAssertTrue(middle.contains("Czy zrobić jeszcze jedną serię?"))
        XCTAssertFalse(end.contains("Czy zrobić jeszcze jedną serię?"))
    }
}
