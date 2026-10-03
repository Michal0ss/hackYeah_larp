import XCTest
import Contracts
@testable import Insights

final class InsightEngineTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 8))!
    private lazy var engine = InsightEngine(calendar: calendar)

    private func day(_ ago: Int) -> Date { calendar.date(byAdding: .day, value: -ago, to: now)! }

    private func snapshot(ago: Int = 0, sleep: Int = 450, hrv: Int = 46, rhr: Int = 56) -> RecoverySnapshot {
        RecoverySnapshot(date: day(ago), sleepMinutes: sleep, restingHeartRate: rhr, hrvMs: hrv,
                         restingHeartRateBaseline: 56, hrvBaselineMs: 46)
    }

    private func checkIn(ago: Int = 0, mood: Int = 4, stress: Int = 2, energy: Int = 4, note: String? = nil) -> CheckIn {
        CheckIn(date: day(ago), mood: mood, stress: stress, energy: energy, note: note)
    }

    private func finding(_ id: String = "torso_lean_high", affected: Int = 3, severity: FindingSeverity = .major) -> TechniqueFinding {
        TechniqueFinding(id: id, title: "Pochylenie tułowia", detail: "", severity: severity, repsAffected: affected, repsTotal: 5)
    }

    private func technique(ago: Int = 0, score: Int = 80, findings: [TechniqueFinding] = [], substitute: String? = nil) -> TechniqueResult {
        TechniqueResult(exerciseId: "squat", date: day(ago), score: score, componentScores: [:], findings: findings,
                        reps: [], substituteExerciseId: substitute)
    }

    private func input(snapshots: [RecoverySnapshot] = [], checkIns: [CheckIn] = [], techniques: [TechniqueResult] = []) -> InsightInput {
        InsightInput(snapshots: snapshots, checkIns: checkIns, techniqueResults: techniques, catalog: SampleData.catalog, now: now)
    }

    // MARK: Decision

    func testGoodDayTrains() {
        let r = engine.recommend(input(snapshots: [snapshot()], checkIns: [checkIn()], techniques: [technique()]))
        XCTAssertEqual(r.decision, .train)
        XCTAssertEqual(r.headline, "Trenuj według planu")
        XCTAssertTrue(r.factors.allSatisfy { !$0.isNegative })
        XCTAssertNil(r.careFlag)
    }

    func testNoDataTrainsAndSaysWhatIsMissing() {
        let r = engine.recommend(input())
        XCTAssertEqual(r.decision, .train)
        XCTAssertTrue(r.suggestedAction.contains("Nie mam danych o regeneracji"))
        XCTAssertTrue(r.factors.isEmpty)
    }

    func testYesterdaysSnapshotIsNotUsedAsToday() {
        let r = engine.recommend(input(snapshots: [snapshot(ago: 1, sleep: 300)]))
        XCTAssertEqual(r.decision, .train)
        XCTAssertTrue(r.factors.isEmpty)
    }

    func testSingleSignalAdapts() {
        let r = engine.recommend(input(snapshots: [snapshot(sleep: 340)], checkIns: [checkIn()]))
        XCTAssertEqual(r.decision, .adapt)
        XCTAssertEqual(r.factors.first { $0.source == .sleep }?.isNegative, true)
        XCTAssertEqual(r.factors.first { $0.source == .sleep }?.text, "Sen 5 h 40 min")
    }

    func testPrototypeExampleThreeSignalsAdaptsNotRests() {
        // Sleep 5:40, HRV -17%, stress 4, resting HR +5 (not above the limit) and a torso finding.
        let r = engine.recommend(input(
            snapshots: [snapshot(sleep: 340, hrv: 38, rhr: 61)],
            checkIns: [checkIn(mood: 3, stress: 4, energy: 3)],
            techniques: [technique(score: 72, findings: [finding()], substitute: "goblet_squat")]))
        XCTAssertEqual(r.decision, .adapt)
        XCTAssertEqual(r.factors.filter(\.isNegative).map(\.source), [.sleep, .hrv, .checkIn, .technique])
        XCTAssertTrue(r.suggestedAction.contains("przysiad kielichowy"))
    }

    func testFourRecoverySignalsRest() {
        let r = engine.recommend(input(snapshots: [snapshot(sleep: 330, hrv: 36, rhr: 63)], checkIns: [checkIn(stress: 5)]))
        XCTAssertEqual(r.decision, .rest)
        XCTAssertEqual(r.headline, "Dziś regeneracja")
    }

    func testTechniqueAloneAdaptsButNeverRests() {
        let r = engine.recommend(input(snapshots: [snapshot()], checkIns: [checkIn()],
                                       techniques: [technique(score: 40, findings: [finding(affected: 5)])]))
        XCTAssertEqual(r.decision, .adapt)
        XCTAssertEqual(r.headline, "Dziś trening z uwagą na technikę")
    }

    func testLowScoreWithoutRepeatedFindingIsStillASignal() {
        let r = engine.recommend(input(snapshots: [snapshot()], techniques: [technique(score: 55)]))
        XCTAssertEqual(r.decision, .adapt)
    }

    func testFindingInMinorityOfRepsIsNotASignal() {
        let r = engine.recommend(input(snapshots: [snapshot()], techniques: [technique(score: 80, findings: [finding(affected: 2)])]))
        XCTAssertEqual(r.decision, .train)
    }

    func testThresholdBoundaries() {
        XCTAssertEqual(engine.recommend(input(snapshots: [snapshot(sleep: 360)])).decision, .train)
        XCTAssertEqual(engine.recommend(input(snapshots: [snapshot(sleep: 359)])).decision, .adapt)
        XCTAssertEqual(engine.recommend(input(snapshots: [snapshot(rhr: 61)])).decision, .train)
        XCTAssertEqual(engine.recommend(input(snapshots: [snapshot(rhr: 62)])).decision, .adapt)
        XCTAssertEqual(engine.recommend(input(checkIns: [checkIn(stress: 3)])).decision, .train)
        XCTAssertEqual(engine.recommend(input(checkIns: [checkIn(stress: 4)])).decision, .adapt)
        XCTAssertEqual(engine.recommend(input(checkIns: [checkIn(energy: 2)])).decision, .adapt)
    }

    func testRestThresholdComesFromConfig() {
        var t = InsightThresholds.default
        t.decision.restFromSignals = 2
        let strict = InsightEngine(thresholds: t, calendar: calendar)
        XCTAssertEqual(strict.recommend(input(snapshots: [snapshot(sleep: 300, hrv: 30)])).decision, .rest)
    }

    func testSimulatedFlagFollowsData() {
        var s = snapshot()
        s.isSimulated = true
        XCTAssertTrue(engine.recommend(input(snapshots: [s])).isSimulated)
        XCTAssertFalse(engine.recommend(input(snapshots: [snapshot()])).isSimulated)
    }

    // MARK: Care pathway

    func testRepeatedFindingInThreeAnalysesRaisesCareFlag() {
        let results = [0, 6, 12].map { technique(ago: $0, score: 70, findings: [finding()]) }
        let r = engine.recommend(input(snapshots: [snapshot()], techniques: results))
        XCTAssertNotNil(r.careFlag)
        XCTAssertTrue(r.careFlag!.reason.contains("3 analizach"))
    }

    func testFindingTwiceOrOutsideWindowDoesNotRaiseCareFlag() {
        let two = [0, 6].map { technique(ago: $0, findings: [finding()]) }
        XCTAssertNil(engine.recommend(input(techniques: two)).careFlag)
        let old = [0, 6, 20].map { technique(ago: $0, findings: [finding()]) }
        XCTAssertNil(engine.recommend(input(techniques: old)).careFlag)
    }

    func testGoodFindingsDoNotCount() {
        let results = [0, 3, 6].map { technique(ago: $0, findings: [finding("depth_ok", affected: 0, severity: .good)]) }
        XCTAssertNil(engine.recommend(input(techniques: results)).careFlag)
    }

    func testPainInNoteRaisesCareFlag() {
        XCTAssertNotNil(engine.recommend(input(checkIns: [checkIn(note: "Dziś ciągnie mnie w kolanie przy przysiadzie")])).careFlag)
        XCTAssertNotNil(engine.recommend(input(checkIns: [checkIn(note: "BÓL w plecach")])).careFlag)
        XCTAssertNil(engine.recommend(input(checkIns: [checkIn(note: "Spałam dobrze, ale boję się deszczu")])).careFlag)
    }

    func testPersistentWorryingRecoveryAndLowWellbeingRaisesCareFlag() {
        let snaps = (0..<3).map { snapshot(ago: $0, sleep: 320, hrv: 36) }
        let checks = (0..<3).map { checkIn(ago: $0, mood: 2, stress: 4) }
        let r = engine.recommend(input(snapshots: snaps, checkIns: checks))
        XCTAssertNotNil(r.careFlag)
        XCTAssertFalse(r.careFlag!.reason.lowercased().contains("masz "), "no diagnosis wording")
    }

    func testPersistentPatternNeedsAllDays() {
        let snaps = (0..<3).map { snapshot(ago: $0, sleep: 320, hrv: 36) }
        var checks = (0..<3).map { checkIn(ago: $0, mood: 2, stress: 4) }
        checks[1] = checkIn(ago: 1, mood: 4, stress: 2)
        XCTAssertNil(engine.recommend(input(snapshots: snaps, checkIns: checks)).careFlag)
    }

    // MARK: Texts and config

    func testTextsAvoidDiagnosisWording() {
        let banned = ["masz uraz", "diagnoz", "choroba", "uszkodz", "nie wolno"]
        let scenarios: [InsightInput] = [
            input(),
            input(snapshots: [snapshot(sleep: 300, hrv: 30, rhr: 66)], checkIns: [checkIn(stress: 5, energy: 1)]),
            input(snapshots: [snapshot(sleep: 340)], techniques: [0, 5, 9].map { technique(ago: $0, score: 50, findings: [finding()]) }),
            input(checkIns: [checkIn(note: "boli kolano")]),
        ]
        for s in scenarios {
            let r = engine.recommend(s)
            let all = ([r.headline, r.suggestedAction, r.careFlag?.reason ?? ""] + r.factors.map(\.text)).joined(separator: " ").lowercased()
            for word in banned {
                // "To nie jest diagnoza" is the allowed disclaimer form.
                XCTAssertFalse(all.replacingOccurrences(of: "nie jest diagnoza", with: "").replacingOccurrences(of: "nie diagnoza", with: "").contains(word), "\(word) in: \(all)")
            }
        }
    }

    func testBundledThresholdsMatchContentConfigFile() throws {
        // Packages/Core/Tests/InsightsTests/<file> -> repo root is five levels up from the file.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("content/config/insights.json")
        let decoded = try InsightThresholds.decode(from: Data(contentsOf: url))
        XCTAssertEqual(decoded, InsightThresholds.default)
    }

    func testMissingConfigKeysFallBackToDefaults() throws {
        let t = try InsightThresholds.decode(from: Data(#"{"decision":{"restFromSignals":5}}"#.utf8))
        XCTAssertEqual(t.decision.restFromSignals, 5)
        XCTAssertEqual(t.signals, InsightThresholds.default.signals)
    }

    // MARK: Service on sample data

    func testServiceOnSampleServicesMatchesPrototype() async {
        let s = SampleServices()
        let service = InsightRecommendationService(recovery: s, checkIns: s, technique: s, catalog: s)
        let r = await service.todayRecommendation()
        XCTAssertEqual(r.decision, SampleData.recommendation.decision)
        XCTAssertEqual(r.decision, .adapt)
        XCTAssertTrue(r.isSimulated)
        XCTAssertEqual(Set(r.factors.filter(\.isNegative).map(\.source)), [.sleep, .hrv, .checkIn, .technique])
    }
}
