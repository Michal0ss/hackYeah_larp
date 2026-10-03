import XCTest
import Contracts
@testable import Insights

final class ProgressReportTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 9))!

    private func day(_ ago: Int) -> Date { calendar.date(byAdding: .day, value: -ago, to: now)! }

    private func result(ago: Int, score: Int, components: [String: Int] = [:]) -> TechniqueResult {
        TechniqueResult(exerciseId: "squat", date: day(ago), score: score, componentScores: components, findings: [], reps: [])
    }

    private func snapshot(ago: Int, sleep: Int = 450, hrv: Int = 46, rhr: Int = 56) -> RecoverySnapshot {
        RecoverySnapshot(date: day(ago), sleepMinutes: sleep, restingHeartRate: rhr, hrvMs: hrv,
                         restingHeartRateBaseline: 56, hrvBaselineMs: 46)
    }

    private func checkIn(ago: Int, mood: Int) -> CheckIn { CheckIn(date: day(ago), mood: mood, stress: 3, energy: 3) }

    private func weighted(ago: Int, exerciseId: String = "squat", kg: Double) -> WeightedSet {
        WeightedSet(exerciseId: exerciseId, date: day(ago), weightKg: kg)
    }

    private func make(results: [TechniqueResult] = [], snapshots: [RecoverySnapshot] = [], checkIns: [CheckIn] = [],
                      weightedSets: [WeightedSet] = []) -> ProgressReport {
        ProgressReport.make(results: results, snapshots: snapshots, checkIns: checkIns, weightedSets: weightedSets,
                            now: now, calendar: calendar)
    }

    func testEmpty() {
        let r = make()
        XCTAssertTrue(r.isEmpty)
        XCTAssertNil(r.trendSentence)
    }

    // MARK: Technique

    func testTechniqueIsOldestFirstWithDeltaFromStart() throws {
        let r = make(results: [result(ago: 0, score: 72), result(ago: 21, score: 58), result(ago: 8, score: 68)])
        let t = try XCTUnwrap(r.technique)
        XCTAssertEqual(t.points.map(\.score), [58, 68, 72])
        XCTAssertEqual(t.latest, 72)
        XCTAssertEqual(t.deltaFromStart, 14)
        XCTAssertTrue(t.summary.hasPrefix("Wynik rośnie od 3 analiz."))
    }

    func testSingleAnalysisHasNoTrendClaim() throws {
        let t = try XCTUnwrap(make(results: [result(ago: 0, score: 72)]).technique)
        XCTAssertEqual(t.deltaFromStart, 0)
        XCTAssertTrue(t.summary.hasPrefix("To pierwsza analiza."))
    }

    func testFallingAndStableWording() throws {
        XCTAssertTrue(try XCTUnwrap(make(results: [result(ago: 5, score: 80), result(ago: 0, score: 70)]).technique).summary.hasPrefix("Wynik jest niższy"))
        XCTAssertTrue(try XCTUnwrap(make(results: [result(ago: 5, score: 70), result(ago: 0, score: 71)]).technique).summary.hasPrefix("Wynik jest stabilny"))
    }

    func testStrongestAndWeakestComponentFromTheLatestAnalysis() throws {
        let comps = ["depth": 88, "torso": 58, "repeatability": 76, "tempo": 70]
        let t = try XCTUnwrap(make(results: [result(ago: 5, score: 60), result(ago: 0, score: 72, components: comps)]).technique)
        XCTAssertTrue(t.summary.contains("Najmocniejsza strona: głębokość."))
        XCTAssertTrue(t.summary.contains("Do poprawy: tułów."))
    }

    func testNoImprovementHintWhenAllComponentsAreGood() throws {
        let comps = ["depth": 88, "torso": 80, "repeatability": 76, "tempo": 90]
        let t = try XCTUnwrap(make(results: [result(ago: 0, score: 85, components: comps)]).technique)
        XCTAssertFalse(t.summary.contains("Do poprawy"))
    }

    // MARK: Recovery and mood

    func testRecoveryIndexValues() {
        XCTAssertEqual(ProgressReport.recoveryIndex(snapshot(ago: 0)), 100)
        // Prototype day: 5 h 40, HRV -17%, resting heart rate +5.
        XCTAssertEqual(ProgressReport.recoveryIndex(snapshot(ago: 0, sleep: 340, hrv: 38, rhr: 61)), 67)
        // Better than baseline is not rewarded beyond full marks.
        XCTAssertEqual(ProgressReport.recoveryIndex(snapshot(ago: 0, sleep: 600, hrv: 80, rhr: 50)), 100)
        XCTAssertEqual(ProgressReport.recoveryIndex(snapshot(ago: 0, sleep: 0, hrv: 0, rhr: 80)), 0)
    }

    func testMoodScale() {
        XCTAssertEqual([1, 2, 3, 4, 5, 0, 9].map(ProgressReport.moodScale), [0, 25, 50, 75, 100, 0, 100])
    }

    func testSeriesAreOldestFirstAndLimitedToTheLastFourteenDays() {
        let snaps = (0..<20).map { snapshot(ago: $0) }
        let checks = (0..<20).map { checkIn(ago: $0, mood: 3) }
        let r = make(snapshots: snaps, checkIns: checks)
        XCTAssertEqual(r.recovery.count, 14)
        XCTAssertEqual(r.mood.count, 14)
        XCTAssertEqual(r.recovery.map(\.date), r.recovery.map(\.date).sorted())
        XCTAssertEqual(r.mood.last?.date, calendar.startOfDay(for: now))
    }

    func testOneMoodPerDayLatestWins() {
        let early = CheckIn(date: calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now)!, mood: 2, stress: 3, energy: 3)
        let late = CheckIn(date: calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now)!, mood: 5, stress: 3, energy: 3)
        let r = make(checkIns: [early, late])
        XCTAssertEqual(r.mood.map(\.value), [100])
    }

    // MARK: Trend sentence

    func testNeedsFourPointsForATrend() {
        XCTAssertNil(make(snapshots: (0..<3).map { snapshot(ago: $0) }).trendSentence)
    }

    func testRecoveryAndMoodDropWithReasons() {
        var snaps = (2..<14).map { snapshot(ago: $0) }
        snaps.append(snapshot(ago: 1, sleep: 340, hrv: 38, rhr: 61))
        snaps.append(snapshot(ago: 0, sleep: 340, hrv: 38, rhr: 61))
        var checks = (2..<14).map { checkIn(ago: $0, mood: 4) }
        checks.append(checkIn(ago: 1, mood: 2))
        checks.append(checkIn(ago: 0, mood: 2))
        let r = make(snapshots: snaps, checkIns: checks)
        XCTAssertEqual(r.trendSentence, "W ostatnich dwóch dniach regeneracja i nastrój spadły: krótszy sen i niższe HRV.")
    }

    func testOnlyRecoveryDrops() {
        var snaps = (2..<10).map { snapshot(ago: $0) }
        snaps.append(snapshot(ago: 1, sleep: 300))
        snaps.append(snapshot(ago: 0, sleep: 300))
        let checks = (0..<10).map { checkIn(ago: $0, mood: 4) }
        XCTAssertEqual(make(snapshots: snaps, checkIns: checks).trendSentence, "W ostatnich dwóch dniach regeneracja spadła: krótszy sen.")
    }

    func testImprovementAndStable() {
        var snaps = (2..<10).map { snapshot(ago: $0, sleep: 330) }
        snaps.append(snapshot(ago: 1))
        snaps.append(snapshot(ago: 0))
        XCTAssertTrue(make(snapshots: snaps).trendSentence!.contains("lepiej"))
        XCTAssertEqual(make(snapshots: (0..<10).map { snapshot(ago: $0) }).trendSentence, "Regeneracja i nastrój są stabilne.")
    }

    // MARK: Strength

    func testNoWeightedSetsMeansNoStrengthProgress() {
        XCTAssertNil(make().strength)
    }

    func testStrengthIsOldestFirstWithDeltaFromStart() throws {
        let r = make(weightedSets: [weighted(ago: 10, kg: 40), weighted(ago: 5, kg: 45), weighted(ago: 0, kg: 50)])
        let s = try XCTUnwrap(r.strength)
        XCTAssertEqual(s.exerciseId, "squat")
        XCTAssertEqual(s.points.map(\.weightKg), [40, 45, 50])
        XCTAssertEqual(s.latest, 50)
        XCTAssertEqual(s.deltaFromStart, 10)
        XCTAssertTrue(s.summary.hasPrefix("Ciężar rośnie"))
    }

    func testSameDayTakesTheHeaviestSet() throws {
        // A warm-up followed by the working weight on the same day should not look like two separate days.
        let r = make(weightedSets: [weighted(ago: 0, kg: 20), weighted(ago: 0, kg: 50), weighted(ago: 0, kg: 45)])
        let s = try XCTUnwrap(r.strength)
        XCTAssertEqual(s.points.count, 1)
        XCTAssertEqual(s.points.first?.weightKg, 50)
    }

    func testPicksTheExerciseLoggedOnTheMostDays() throws {
        let sets = [weighted(ago: 10, exerciseId: "deadlift", kg: 80)]
            + (0..<3).map { weighted(ago: $0, exerciseId: "squat", kg: 40) }
        let s = try XCTUnwrap(make(weightedSets: sets).strength)
        XCTAssertEqual(s.exerciseId, "squat")
        XCTAssertEqual(s.points.count, 3)
    }

    func testSingleWeightHasNoTrendClaim() throws {
        let s = try XCTUnwrap(make(weightedSets: [weighted(ago: 0, kg: 40)]).strength)
        XCTAssertEqual(s.deltaFromStart, 0)
        XCTAssertTrue(s.summary.hasPrefix("To pierwszy zapisany ciężar."))
    }

    func testFallingAndStableWeightWording() throws {
        let falling = make(weightedSets: [weighted(ago: 5, kg: 50), weighted(ago: 0, kg: 45)])
        XCTAssertTrue(try XCTUnwrap(falling.strength).summary.hasPrefix("Ostatni ciężar jest niższy"))
        let stable = make(weightedSets: [weighted(ago: 5, kg: 50), weighted(ago: 0, kg: 50.25)])
        XCTAssertTrue(try XCTUnwrap(stable.strength).summary.hasPrefix("Ciężar jest stabilny"))
    }

    func testStrengthIsNotLimitedToTheRecoveryWindow() throws {
        // Strength is a trend across sessions, like technique, not a daily health signal like recovery/mood.
        let s = try XCTUnwrap(make(weightedSets: [weighted(ago: 60, kg: 40), weighted(ago: 0, kg: 50)]).strength)
        XCTAssertEqual(s.points.count, 2)
    }

    // MARK: Sample data

    func testSampleMatchesThePrototype() throws {
        let results = ProgressSample.techniqueResults(now: now, calendar: calendar)
        XCTAssertEqual(results.map(\.score), [58, 61, 65, 68, 70, 72])
        XCTAssertTrue(results.allSatisfy(\.isSimulated))
        let report = make(results: results)
        XCTAssertEqual(report.technique?.deltaFromStart, 14)
        // Three analyses with the torso finding inside 14 days -> care card with 68 / 70 / 72.
        let care = CarePathway(calendar: calendar).assess(snapshots: [], checkIns: [], techniqueResults: results, now: now)
        XCTAssertEqual(care?.evidence.map(\.score), [68, 70, 72])
        XCTAssertEqual(ProgressSample.checkIns(now: now, calendar: calendar).count, 14)
    }
}
