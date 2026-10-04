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

    private func set(ago: Int, exerciseId: String = "squat") -> LoggedActivity {
        LoggedActivity(exerciseId: exerciseId, date: day(ago))
    }

    private func make(results: [TechniqueResult] = [], snapshots: [RecoverySnapshot] = [], checkIns: [CheckIn] = [],
                      activitySets: [LoggedActivity] = []) -> ProgressReport {
        ProgressReport.make(results: results, snapshots: snapshots, checkIns: checkIns, activitySets: activitySets,
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

    // MARK: Activity

    func testActivityGridIsWholeMondayToSundayWeeksEndingThisWeek() throws {
        let a = ActivityLog.make(sets: [], weeks: 12, now: now, calendar: calendar)
        XCTAssertEqual(a.days.count, 12 * 7)
        let first = try XCTUnwrap(a.days.first)
        XCTAssertEqual(calendar.component(.weekday, from: first.date), 2, "the grid starts on a Monday")
        let today = calendar.startOfDay(for: now)
        XCTAssertTrue(a.days.contains { $0.date == today && $0.setCount == 0 })
        // Days after today keep the rectangle full but carry no data.
        XCTAssertTrue(a.days.filter { $0.date > today }.allSatisfy { $0.setCount == nil })
        XCTAssertTrue(a.days.filter { $0.date <= today }.allSatisfy { $0.setCount != nil })
    }

    func testActivityCountsSetsPerDayAndIgnoresOlderThanTheWindow() throws {
        let sets = [set(ago: 0), set(ago: 0), set(ago: 0), set(ago: 2), set(ago: 400)]
        let a = make(activitySets: sets).activity
        XCTAssertEqual(a.days.first { $0.date == calendar.startOfDay(for: day(0)) }?.setCount, 3)
        XCTAssertEqual(a.days.first { $0.date == calendar.startOfDay(for: day(2)) }?.setCount, 1)
        XCTAssertEqual(a.days.compactMap(\.setCount).reduce(0, +), 4, "the set from 400 days ago is outside the grid")
    }

    func testEmptyLogHasNoActivityAndSaysSo() {
        let r = make()
        XCTAssertFalse(r.activity.hasAnyActivity)
        XCTAssertEqual(r.activity.currentStreakDays, 0)
        XCTAssertNil(r.activity.topExerciseId)
        XCTAssertEqual(r.activity.summary, "Brak treningów w ostatnich 14 dniach.")
    }

    func testAnyLoggedSetMakesTheReportNonEmpty() {
        XCTAssertFalse(make(activitySets: [set(ago: 1)]).isEmpty)
    }

    func testStreakCountsConsecutiveDaysEndingToday() {
        XCTAssertEqual(make(activitySets: [set(ago: 0), set(ago: 1), set(ago: 2), set(ago: 4)]).activity.currentStreakDays, 3)
        // No set today: the streak is broken, even with a set yesterday.
        XCTAssertEqual(make(activitySets: [set(ago: 1), set(ago: 2)]).activity.currentStreakDays, 0)
    }

    func testSummaryCountsTrainingDaysAndSetsWithPolishPlurals() {
        let sets = [set(ago: 0), set(ago: 0), set(ago: 3), set(ago: 5), set(ago: 5)]
        XCTAssertEqual(make(activitySets: sets).activity.summary, "W ostatnim tygodniu: 3 treningi, 5 serii.")
        XCTAssertEqual(make(activitySets: [set(ago: 0)]).activity.summary, "W ostatnim tygodniu: 1 trening, 1 seria.")
    }

    func testSummaryComparesWithTheWeekBefore() {
        let more = [set(ago: 0), set(ago: 2), set(ago: 9)]
        XCTAssertTrue(make(activitySets: more).activity.summary.hasSuffix("Więcej treningów niż tydzień wcześniej."))
        let fewer = [set(ago: 0), set(ago: 8), set(ago: 10)]
        XCTAssertTrue(make(activitySets: fewer).activity.summary.hasSuffix("Mniej treningów niż tydzień wcześniej."))
        XCTAssertEqual(make(activitySets: [set(ago: 9)]).activity.summary, "W tym tygodniu bez treningu. W poprzednim: 1 trening.")
    }

    func testTopExerciseIsTheMostLoggedInTheLastWeek() {
        let sets = [set(ago: 0, exerciseId: "pushup"), set(ago: 1, exerciseId: "squat"), set(ago: 2, exerciseId: "squat"),
                    set(ago: 20, exerciseId: "pushup"), set(ago: 21, exerciseId: "pushup"), set(ago: 22, exerciseId: "pushup")]
        XCTAssertEqual(make(activitySets: sets).activity.topExerciseId, "squat", "older sets don't count toward this week")
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
