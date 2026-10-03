import XCTest
import Contracts
@testable import Insights

final class CarePathwayTests: XCTestCase {
    private var calendar = Calendar(identifier: .gregorian)
    private lazy var now: Date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 8))!
    private lazy var pathway = CarePathway(calendar: calendar)

    private func day(_ ago: Int) -> Date { calendar.date(byAdding: .day, value: -ago, to: now)! }

    private func finding(_ id: String = "torso_lean_high", affected: Int = 3) -> TechniqueFinding {
        TechniqueFinding(id: id, title: "Pochylenie tułowia", detail: "", severity: .major, repsAffected: affected, repsTotal: 5)
    }

    private func result(ago: Int, score: Int = 70, findings: [TechniqueFinding]) -> TechniqueResult {
        TechniqueResult(exerciseId: "squat", date: day(ago), score: score, componentScores: [:], findings: findings, reps: [])
    }

    private func checkIn(ago: Int = 0, mood: Int = 4, stress: Int = 2, note: String? = nil) -> CheckIn {
        CheckIn(date: day(ago), mood: mood, stress: stress, energy: 3, note: note)
    }

    private func snapshot(ago: Int, sleep: Int = 450, hrv: Int = 46) -> RecoverySnapshot {
        RecoverySnapshot(date: day(ago), sleepMinutes: sleep, restingHeartRate: 56, hrvMs: hrv,
                         restingHeartRateBaseline: 56, hrvBaselineMs: 46)
    }

    private func assess(snapshots: [RecoverySnapshot] = [], checkIns: [CheckIn] = [], results: [TechniqueResult] = []) -> CareAssessment? {
        pathway.assess(snapshots: snapshots, checkIns: checkIns, techniqueResults: results, now: now)
    }

    func testNothingToReport() {
        XCTAssertNil(assess())
        XCTAssertNil(assess(snapshots: [snapshot(ago: 0)], checkIns: [checkIn()], results: [result(ago: 0, findings: [finding()])]))
    }

    func testRepeatedFindingGivesEvidenceOldestFirstLikeThePrototype() throws {
        // Prototype: 22 Sep 68 (4 of 5), 28 Sep 70 (3 of 5), today 72 (3 of 5).
        let results = [result(ago: 0, score: 72, findings: [finding(affected: 3)]),
                       result(ago: 9, score: 70, findings: [finding(affected: 3)]),
                       result(ago: 14, score: 68, findings: [finding(affected: 4)])]
        let a = try XCTUnwrap(assess(results: results))
        XCTAssertEqual(a.kind, .repeatedFinding(id: "torso_lean_high", title: "Pochylenie tułowia"))
        XCTAssertEqual(a.evidence.map(\.score), [68, 70, 72])
        XCTAssertEqual(a.evidence.first?.text, "pochylenie tułowia w 4 z 5 powtórzeń")
        XCTAssertEqual(a.evidence.map(\.date), a.evidence.map(\.date).sorted())
        XCTAssertEqual(a.steps.count, 3)
        XCTAssertTrue(a.flag.reason.contains("3 analizach"))
    }

    func testEvidenceOnlyContainsTheAnalysesWithThatFinding() throws {
        let results = [result(ago: 0, findings: [finding()]), result(ago: 3, findings: [finding()]),
                       result(ago: 5, findings: [finding("depth_low")]), result(ago: 7, findings: [finding()])]
        let a = try XCTUnwrap(assess(results: results))
        XCTAssertEqual(a.evidence.count, 3)
    }

    func testMostFrequentFindingWinsAndTiesAreDeterministic() throws {
        let both = (0..<3).map { result(ago: $0 * 2, findings: [finding("b_second"), finding("a_first")]) }
        let a = try XCTUnwrap(assess(results: both))
        XCTAssertEqual(a.kind, .repeatedFinding(id: "a_first", title: "Pochylenie tułowia"))
    }

    func testPainNoteGivesEvidenceWithTheUsersWordsAndOutranksAnalyses() throws {
        let results = (0..<3).map { result(ago: $0 * 3, findings: [finding()]) }
        let a = try XCTUnwrap(assess(checkIns: [checkIn(note: "Ciągnie mnie w kolanie")], results: results))
        XCTAssertEqual(a.kind, .painNote)
        XCTAssertEqual(a.evidence.count, 1)
        XCTAssertTrue(a.evidence[0].text.contains("Ciągnie mnie w kolanie"))
    }

    func testOldPainNoteIsIgnored() {
        XCTAssertNil(assess(checkIns: [checkIn(ago: 5, note: "boli kolano")]))
    }

    func testPersistentRecoveryListsEachDay() throws {
        let snaps = (0..<3).map { snapshot(ago: $0, sleep: 320, hrv: 36) }
        let checks = (0..<3).map { checkIn(ago: $0, mood: 2, stress: 4) }
        let a = try XCTUnwrap(assess(snapshots: snaps, checkIns: checks))
        XCTAssertEqual(a.kind, .persistentRecovery)
        XCTAssertEqual(a.evidence.count, 3)
        XCTAssertEqual(a.evidence.map(\.date), a.evidence.map(\.date).sorted())
    }

    func testStepsAndTextsAvoidDiagnosisAndAlwaysPointToASpecialist() throws {
        let banned = ["masz uraz", "diagnoz", "choroba", "uszkodz", "nie wolno", "depresj"]
        let pain = try XCTUnwrap(assess(checkIns: [checkIn(note: "boli")]))
        let repeated = try XCTUnwrap(assess(results: (0..<3).map { result(ago: $0, findings: [finding()]) }))
        let persistent = try XCTUnwrap(assess(snapshots: (0..<3).map { snapshot(ago: $0, sleep: 300, hrv: 30) },
                                              checkIns: (0..<3).map { checkIn(ago: $0, mood: 1, stress: 5) }))
        for a in [pain, repeated, persistent] {
            let all = ([a.flag.reason] + a.steps).joined(separator: " ").lowercased()
            for w in banned {
                // "To nie jest diagnoza" and "sygnał, nie diagnoza" are the allowed disclaimer forms.
                let cleaned = all.replacingOccurrences(of: "nie jest diagnoza", with: "").replacingOccurrences(of: "nie diagnoza", with: "")
                XCTAssertFalse(cleaned.contains(w), "\(w) in \(all)")
            }
            XCTAssertTrue(all.contains("specjalist") || all.contains("fizjoterapeut") || all.contains("lekarz"), all)
        }
    }

    func testDisclaimerMentionsDoctorAndNotMedicalAdvice() {
        XCTAssertTrue(CarePathway.disclaimer.contains("lekarzem"))
        XCTAssertTrue(CarePathway.disclaimer.contains("To nie jest porada medyczna"))
    }

    func testEngineCareFlagMatchesPathway() {
        let results = (0..<3).map { result(ago: $0 * 4, findings: [finding()]) }
        let engine = InsightEngine(calendar: calendar)
        let flag = engine.careFlag(InsightInput(snapshots: [], checkIns: [], techniqueResults: results, now: now))
        XCTAssertEqual(flag, assess(results: results)?.flag)
    }
}
