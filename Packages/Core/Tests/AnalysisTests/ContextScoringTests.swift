import XCTest
import Contracts
import LiveSet
@testable import Analysis

final class ContextScoringTests: XCTestCase {
    private let base = AngleReference()

    private func rep(_ index: Int, torsoLean: Double, hipBelowKnee: Bool = true, kneeAngle: Double = 70) -> RepMetrics {
        RepMetrics(index: index, minKneeAngle: kneeAngle, hipBelowKnee: hipBelowKnee, torsoLeanDegrees: torsoLean,
                   descentSeconds: 3, ascentSeconds: 2)
    }

    // MARK: Measuring the clip

    func testTheProportionIsMeasuredFromTheClipForASquat() {
        // The synthetic squat has a thigh of about 0.82 of its torso. With a lower reference that is "long", so the
        // clip's own proportion has to show up as an allowance for the torso lean.
        let frames = SimulatedSquat(kind: .squat).frames()
        var rules = ContextRules()
        rules.thighToTorsoReference = 0.70
        let adjustment = ContextScoring.adjustment(for: .standard, kind: .squat, frames: frames, reference: base, rules: rules)
        XCTAssertGreaterThan(adjustment.torsoLeanExtra, 5)
        XCTAssertLessThanOrEqual(adjustment.torsoLeanExtra, rules.torsoLeanProportionMax)
        XCTAssertEqual(adjustment.reference.squatTorsoLeanMax, base.squatTorsoLeanMax + adjustment.torsoLeanExtra, accuracy: 1e-9)
    }

    func testStandardProportionsAndStandardContextChangeNothing() {
        let frames = SimulatedSquat(kind: .squat).frames()
        let adjustment = ContextScoring.adjustment(for: .standard, kind: .squat, frames: frames, reference: base)
        XCTAssertTrue(adjustment.isStandard)
        XCTAssertEqual(adjustment.reference, base)
    }

    func testAClipWithoutRepetitionsHasNoProportionsToMeasure() {
        let adjustment = ContextScoring.adjustment(for: .standard, kind: .squat, frames: [], reference: base)
        XCTAssertTrue(adjustment.isStandard)
    }

    func testProportionsPlayNoPartForOtherExercises() {
        let frames = SimulatedSquat(kind: .pushup).frames()
        var rules = ContextRules()
        rules.thighToTorsoReference = 0.30
        let adjustment = ContextScoring.adjustment(for: .standard, kind: .pushup, frames: frames, reference: base, rules: rules)
        XCTAssertTrue(adjustment.isStandard)
    }

    // MARK: Scoring with the allowances

    func testThresholdsFollowTheAdjustment() {
        let limited = TechniqueContext(lowerBodyMobility: .limited, level: .beginner)
            .adjustment(for: .squat, base: base)
        let thresholds = TechniqueScorer.Thresholds().adjusted(by: limited)
        XCTAssertEqual(thresholds.maxTorsoLeanDegrees, 45 + limited.torsoLeanExtra)
        XCTAssertEqual(thresholds.repeatabilityToleranceDegrees, 15 + 5)
        XCTAssertEqual(thresholds.minControlledDescentSeconds, TechniqueScorer.Thresholds().minControlledDescentSeconds)
        // Standard changes nothing.
        let standard = TechniqueContext.standard.adjustment(for: .squat, base: base)
        XCTAssertEqual(TechniqueScorer.Thresholds().adjusted(by: standard).maxTorsoLeanDegrees, 45)
    }

    func testRecordedSquatWithAForwardLeanScoresBetterForLimitedMobility() {
        let reps = (1...5).map { rep($0, torsoLean: 49) }
        let standard = TechniqueScorer.score(exerciseId: "squat", reps: reps)
        XCTAssertEqual(standard.componentScores["torso"], 0)
        XCTAssertTrue(standard.findings.contains { $0.id == "torso_lean_high" })

        let adjustment = TechniqueContext(lowerBodyMobility: .limited).adjustment(for: .squat, base: base)
        let adapted = TechniqueScorer.score(exerciseId: "squat", reps: reps, thresholds: TechniqueScorer.Thresholds().adjusted(by: adjustment))
        XCTAssertEqual(adapted.componentScores["torso"], 100)
        XCTAssertTrue(adapted.findings.contains { $0.id == "torso_ok" })
        XCTAssertGreaterThan(adapted.score, standard.score)
    }

    func testBeginnersGetMoreRoomInTheSpreadBetweenRepetitions() {
        let reps = [rep(1, torsoLean: 20, kneeAngle: 60), rep(2, torsoLean: 20, kneeAngle: 80), rep(3, torsoLean: 20, kneeAngle: 65)]
        let standard = TechniqueScorer.score(exerciseId: "squat", reps: reps)
        let adjustment = TechniqueContext(level: .beginner).adjustment(for: .squat, base: base)
        let beginner = TechniqueScorer.score(exerciseId: "squat", reps: reps, thresholds: TechniqueScorer.Thresholds().adjusted(by: adjustment))
        XCTAssertGreaterThan(beginner.componentScores["repeatability"] ?? 0, standard.componentScores["repeatability"] ?? 100)
    }

    func testNoContextGivesTheSameScoreAsBefore() {
        let reps = (1...4).map { rep($0, torsoLean: 30 + Double($0)) }
        let before = TechniqueScorer.score(exerciseId: "squat", reps: reps)
        let adjustment = TechniqueContext.standard.adjustment(for: .squat, base: base)
        let after = TechniqueScorer.score(exerciseId: "squat", reps: reps, thresholds: TechniqueScorer.Thresholds().adjusted(by: adjustment))
        XCTAssertEqual(before.score, after.score)
        XCTAssertEqual(before.componentScores, after.componentScores)
        XCTAssertEqual(before.findings, after.findings)
    }
}
