import XCTest
import Contracts
@testable import Insights

final class PlanAdjusterTests: XCTestCase {
    private let adjuster = PlanAdjuster(catalog: SampleData.catalog)
    private let legsDay = SampleData.plan.sessions[0] // squat 4x6-8 120 s (tempo), RDL 3x8-10 90 s, lunge 3x10-12 60 s, plank 3x30-45 45 s

    private func recommendation(_ decision: Decision, negative: [FactorSource] = []) -> DailyRecommendation {
        DailyRecommendation(date: Date(), decision: decision, headline: "", factors: negative.map {
            RecommendationFactor(source: $0, text: "", isNegative: true)
        }, suggestedAction: "")
    }

    private func squatTechnique(substitute: String? = "goblet_squat") -> TechniqueResult {
        TechniqueResult(exerciseId: "squat", date: Date(), score: 72, componentScores: [:], findings: [], reps: [],
                        substituteExerciseId: substitute)
    }

    // MARK: Trenuj

    func testTrainLeavesSessionUntouched() {
        let r = adjuster.adjust(legsDay, for: recommendation(.train))
        XCTAssertEqual(r.session, legsDay)
        XCTAssertFalse(r.isChanged)
        XCTAssertNil(r.session.adaptationNote)
    }

    // MARK: Zmodyfikuj

    func testAdaptRemovesOneSetAndShortensRests() {
        let r = adjuster.adjust(legsDay, for: recommendation(.adapt, negative: [.sleep]))
        XCTAssertEqual(r.session.exercises.map(\.sets), [3, 2, 2, 2])
        XCTAssertEqual(r.session.exercises.map(\.restSeconds), [90, 75, 45, 30])
        XCTAssertEqual(r.session.exercises.map(\.exerciseId), legsDay.exercises.map(\.exerciseId))
        XCTAssertEqual(r.session.exercises.map(\.repsMin), legsDay.exercises.map(\.repsMin), "reps stay as planned")
        XCTAssertEqual(r.session.status, .adapted)
        XCTAssertEqual(r.session.id, legsDay.id)
        XCTAssertEqual(r.original, legsDay)
        XCTAssertTrue(r.changes.first!.hasPrefix("Przysiad: 4 → 3 serie, przerwa 2:00 → 1:30"))
    }

    func testAdaptKeepsTwoSetExercisesAtTwo() {
        let s = PlannedSession(weekday: 1, title: "Mini", exercises: [
            PlannedExercise(exerciseId: "pushup", sets: 2, repsMin: 10, repsMax: 12, restSeconds: 30)])
        let r = adjuster.adjust(s, for: recommendation(.adapt, negative: [.sleep]))
        XCTAssertFalse(r.isChanged, "nothing to lighten")
        XCTAssertEqual(r.session, s)
    }

    func testAdaptSwapsAnalysedExerciseForSubstitute() {
        let r = adjuster.adjust(legsDay, for: recommendation(.adapt, negative: [.sleep, .technique]),
                                technique: squatTechnique(), equipment: .dumbbells)
        XCTAssertEqual(r.session.exercises[0].exerciseId, "goblet_squat")
        XCTAssertEqual(r.session.exercises[0].sets, 3)
        XCTAssertEqual(r.session.exercises[0].tempo, legsDay.exercises[0].tempo, "substitute without own tempo keeps the planned one")
        XCTAssertTrue(r.changes[0].contains("Przysiad zastąpiony: przysiad kielichowy"))
        XCTAssertTrue(r.session.adaptationNote!.contains("uwagi do techniki"))
    }

    func testNoSwapWhenTechniqueDidNotRaiseASignal() {
        let r = adjuster.adjust(legsDay, for: recommendation(.adapt, negative: [.sleep]),
                                technique: squatTechnique(), equipment: .dumbbells)
        XCTAssertEqual(r.session.exercises[0].exerciseId, "squat")
    }

    func testNoSwapForExerciseNotInTheSession() {
        let upper = SampleData.plan.sessions[1]
        let r = adjuster.adjust(upper, for: recommendation(.adapt, negative: [.technique]), technique: squatTechnique())
        XCTAssertEqual(r.session.exercises.map(\.exerciseId), upper.exercises.map(\.exerciseId))
    }

    func testNoSwapWhenSubstituteIsUnknownAlreadyInSessionOrNeedsMoreEquipment() {
        let rec = recommendation(.adapt, negative: [.technique])
        // Unknown id.
        XCTAssertEqual(adjuster.adjust(legsDay, for: rec, technique: squatTechnique(substitute: "nope")).session.exercises[0].exerciseId, "squat")
        // No substitute at all.
        XCTAssertEqual(adjuster.adjust(legsDay, for: rec, technique: squatTechnique(substitute: nil)).session.exercises[0].exerciseId, "squat")
        // Already in the session.
        var withGoblet = legsDay
        withGoblet.exercises.append(PlannedExercise(exerciseId: "goblet_squat", sets: 3, repsMin: 8, repsMax: 10, restSeconds: 60))
        XCTAssertEqual(adjuster.adjust(withGoblet, for: rec, technique: squatTechnique()).session.exercises[0].exerciseId, "squat")
        // Needs more equipment than the user has (goblet squat uses dumbbells, user has none).
        XCTAssertEqual(adjuster.adjust(legsDay, for: rec, technique: squatTechnique(), equipment: Equipment.none).session.exercises[0].exerciseId, "squat")
        // Bodyweight substitute is fine for everyone.
        XCTAssertEqual(adjuster.adjust(legsDay, for: rec, technique: squatTechnique(substitute: "box_squat"), equipment: Equipment.none).session.exercises[0].exerciseId, "box_squat")
    }

    func testEveryExerciseAfterAdjustmentIsInTheCatalog() {
        let r = adjuster.adjust(legsDay, for: recommendation(.adapt, negative: [.technique]), technique: squatTechnique())
        let ids = Set(SampleData.catalog.map(\.id))
        XCTAssertTrue(r.session.exercises.allSatisfy { ids.contains($0.exerciseId) })
    }

    func testAdaptationNoteListsReasonsInPlainWords() {
        let r = adjuster.adjust(legsDay, for: recommendation(.adapt, negative: [.checkIn, .sleep, .hrv]))
        XCTAssertEqual(r.session.adaptationNote, "Lżejszy trening: krótki sen, HRV niżej niż zwykle i podwyższony stres lub niska energia.")
    }

    func testAdjustingTwiceNeverLightensTwice() {
        let rec = recommendation(.adapt, negative: [.sleep])
        let once = adjuster.adjust(legsDay, for: rec)
        let twice = adjuster.adjust(once.session, for: rec)
        XCTAssertEqual(twice.session, once.session)
        XCTAssertFalse(twice.isChanged)
    }

    // MARK: Odpuść

    func testRestTurnsSessionIntoRestDay() {
        let r = adjuster.adjust(legsDay, for: recommendation(.rest, negative: [.sleep, .hrv, .restingHeartRate, .checkIn]))
        XCTAssertTrue(r.isRestDay)
        XCTAssertTrue(r.session.exercises.isEmpty)
        XCTAssertEqual(r.session.title, PlanAdjuster.restDayTitle)
        XCTAssertEqual(r.session.status, .adapted)
        XCTAssertEqual(r.session.weekday, legsDay.weekday)
        XCTAssertTrue(r.session.adaptationNote!.contains("spacer"))
        XCTAssertEqual(r.original, legsDay, "original kept so the user can restore it")
    }

    func testDoneSessionIsNeverChanged() {
        var done = legsDay
        done.status = .done
        XCTAssertFalse(adjuster.adjust(done, for: recommendation(.rest)).isChanged)
        XCTAssertFalse(adjuster.adjust(done, for: recommendation(.adapt, negative: [.sleep])).isChanged)
    }

    func testReasonsWithoutNegativeFactorsStayNeutral() {
        XCTAssertEqual(PlanAdjuster.reasons(recommendation(.adapt)), "sygnały z dzisiejszych danych")
    }

    // MARK: Numbers

    func testShortenedRest() {
        XCTAssertEqual(PlanAdjuster.shortenedRest(120), 90)
        XCTAssertEqual(PlanAdjuster.shortenedRest(90), 75)
        XCTAssertEqual(PlanAdjuster.shortenedRest(60), 45)
        XCTAssertEqual(PlanAdjuster.shortenedRest(45), 30)
        XCTAssertEqual(PlanAdjuster.shortenedRest(30), 30)
        XCTAssertEqual(PlanAdjuster.shortenedRest(0), 0)
        XCTAssertEqual(PlanAdjuster.shortenedRest(35), 30)
    }

    func testPolishSetsWord() {
        XCTAssertEqual([1, 2, 3, 4, 5, 11, 12, 22, 25].map(PlanAdjuster.setsWord),
                       ["seria", "serie", "serie", "serie", "serii", "serii", "serii", "serie", "serii"])
    }

    func testClock() {
        XCTAssertEqual(PlanAdjuster.clock(90), "1:30")
        XCTAssertEqual(PlanAdjuster.clock(120), "2:00")
        XCTAssertEqual(PlanAdjuster.clock(45), "0:45")
    }

    func testTextsAvoidDiagnosisWording() {
        let banned = ["uraz", "diagnoz", "choroba", "uszkodz", "nie wolno"]
        for rec in [recommendation(.adapt, negative: [.sleep, .hrv, .restingHeartRate, .checkIn, .technique]),
                    recommendation(.rest, negative: [.sleep, .hrv, .restingHeartRate, .checkIn])] {
            let r = adjuster.adjust(legsDay, for: rec, technique: squatTechnique())
            let all = (r.changes + [r.session.adaptationNote ?? "", r.session.title]).joined(separator: " ").lowercased()
            for w in banned { XCTAssertFalse(all.contains(w), "\(w) in \(all)") }
        }
    }
}
