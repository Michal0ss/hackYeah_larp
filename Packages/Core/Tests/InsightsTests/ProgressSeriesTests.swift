import XCTest
import Contracts
@testable import Insights

final class ProgressSeriesTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 9))!
    private func day(_ ago: Int, hour: Int = 9) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.date(byAdding: .day, value: -ago, to: now)!)!
    }

    private func result(_ id: String, ago: Int, score: Int, parts: [String: Int] = [:]) -> TechniqueResult {
        TechniqueResult(exerciseId: id, date: day(ago), score: score, componentScores: parts, findings: [], reps: [])
    }

    // MARK: Technique

    func testExercisesAreOrderedByHowOftenTheyWereAnalysed() {
        let results = [result("pushup", ago: 1, score: 70), result("squat", ago: 2, score: 60),
                       result("squat", ago: 3, score: 65), result("pullup", ago: 4, score: 50)]
        XCTAssertEqual(TechniqueSeries.exerciseIds(in: results), ["squat", "pullup", "pushup"])
    }

    func testPlanExercisesAreOfferedForTechniqueEvenWithoutAnalysis() {
        let results = [result("pushup", ago: 1, score: 70)]
        XCTAssertEqual(TechniqueSeries.exerciseIds(in: results, planned: ["squat", "pushup", "row"]), ["squat", "pushup", "row"])
        XCTAssertEqual(TechniqueSeries.exerciseIds(in: results + [result("pullup", ago: 2, score: 50)], planned: ["squat"]),
                       ["squat", "pullup", "pushup"].sorted { $0 == "squat" ? true : $1 == "squat" ? false : $0 < $1 })
    }

    func testPointsAreOneExerciseOldestFirst() {
        let results = [result("squat", ago: 0, score: 72), result("pushup", ago: 1, score: 90), result("squat", ago: 8, score: 58)]
        let points = TechniqueSeries.points(results, exerciseId: "squat")
        XCTAssertEqual(points.map(\.value), [58, 72])
    }

    func testAComponentIsFollowedInsteadOfTheOverallScore() {
        let results = [result("squat", ago: 5, score: 60, parts: ["depth": 40, "torso": 80]),
                       result("squat", ago: 0, score: 70, parts: ["depth": 55, "torso": 82])]
        XCTAssertEqual(TechniqueSeries.points(results, exerciseId: "squat", component: "depth").map(\.value), [40, 55])
    }

    func testAnAnalysisWithoutTheAskedPartIsLeftOutNotDrawnAsZero() {
        let results = [result("squat", ago: 5, score: 60), result("squat", ago: 0, score: 70, parts: ["tempo": 66])]
        XCTAssertEqual(TechniqueSeries.points(results, exerciseId: "squat", component: "tempo").map(\.value), [66])
    }

    func testComponentsAreOnlyThoseThePickedExerciseHasInTheOfferedOrder() {
        let results = [result("squat", ago: 1, score: 70, parts: ["tempo": 60, "depth": 80]),
                       result("pushup", ago: 1, score: 70, parts: ["torso": 50])]
        XCTAssertEqual(TechniqueSeries.components(in: results, exerciseId: "squat"), ["depth", "tempo"])
        XCTAssertEqual(TechniqueSeries.components(in: results, exerciseId: "pushup"), ["torso"])
    }

    // MARK: Load

    private func load(_ id: String = "squat", ago: Int, kg: Double? = nil, reps: Int? = nil, hour: Int = 9) -> LoggedLoad {
        LoggedLoad(exerciseId: id, date: day(ago, hour: hour), weightKg: kg, reps: reps)
    }

    func testWeightTakesTheHeaviestSetOfTheDay() {
        let sets = [load(ago: 0, kg: 20, hour: 9), load(ago: 0, kg: 50, hour: 10), load(ago: 0, kg: 45, hour: 11), load(ago: 7, kg: 40)]
        let points = LoadSeries.points(sets, exerciseId: "squat", metric: .weight, calendar: calendar)
        XCTAssertEqual(points.map(\.value), [40, 50])
    }

    func testRepsTakeTheBestSetOfTheDayAndSkipTimedSets() {
        let sets = [load(ago: 0, reps: 8), load(ago: 0, reps: 12), load(ago: 1, reps: nil), load(ago: 2, reps: 10)]
        let points = LoadSeries.points(sets, exerciseId: "squat", metric: .reps, calendar: calendar)
        XCTAssertEqual(points.map(\.value), [10, 12])
    }

    func testOnlyPlanExercisesAreOfferedInPlanOrderEvenWithNothingLogged() {
        XCTAssertEqual(LoadSeries.exerciseIds(planned: ["row", "squat", "press", "row"]), ["row", "squat", "press"])
    }

    func testExercisesThatDoNotFitTheMetricAreLeftOut() {
        let ids = LoadSeries.exerciseIds(planned: ["squat", "plank", "row"]) { $0 != "plank" }
        XCTAssertEqual(ids, ["squat", "row"])
    }

    func testNoSetsMeansNoPoints() {
        XCTAssertTrue(LoadSeries.points([], exerciseId: "squat", metric: .weight).isEmpty)
        XCTAssertTrue(LoadSeries.exerciseIds(planned: []).isEmpty)
    }
}
