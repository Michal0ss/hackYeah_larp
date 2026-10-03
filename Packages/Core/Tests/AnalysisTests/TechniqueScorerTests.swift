import XCTest
import Contracts
@testable import Analysis

final class TechniqueScorerTests: XCTestCase {
    private func rep(_ index: Int, minKneeAngle: Double, hipBelowKnee: Bool, torsoLeanDegrees: Double,
                     descentSeconds: Double = 3, ascentSeconds: Double = 2) -> RepMetrics {
        RepMetrics(index: index, minKneeAngle: minKneeAngle, hipBelowKnee: hipBelowKnee,
                  torsoLeanDegrees: torsoLeanDegrees, descentSeconds: descentSeconds, ascentSeconds: ascentSeconds)
    }

    func testGoodConsistentRepsScoreHigh() {
        let reps = (1...5).map { rep($0, minKneeAngle: 70, hipBelowKnee: true, torsoLeanDegrees: 20) }

        let result = TechniqueScorer.score(exerciseId: "squat", reps: reps)

        XCTAssertGreaterThanOrEqual(result.score, 90)
        XCTAssertEqual(result.componentScores["depth"], 100)
        XCTAssertEqual(result.componentScores["torso"], 100)
        XCTAssertNil(result.substituteExerciseId)
        XCTAssertTrue(result.findings.contains { $0.id == "depth_ok" })
        XCTAssertTrue(result.findings.contains { $0.id == "torso_ok" })
    }

    func testShallowRepsLowerDepthScoreAndSuggestBoxSquat() {
        let reps = (1...5).map { rep($0, minKneeAngle: 150, hipBelowKnee: false, torsoLeanDegrees: 20) }

        let result = TechniqueScorer.score(exerciseId: "squat", reps: reps)

        XCTAssertEqual(result.componentScores["depth"], 0)
        XCTAssertEqual(result.substituteExerciseId, "box_squat")
        let finding = result.findings.first { $0.id == "depth_shallow" }
        XCTAssertNotNil(finding)
        XCTAssertEqual(finding?.severity, .major)
        XCTAssertEqual(finding?.repsAffected, 5)
    }

    func testHighTorsoLeanLowersTorsoScoreAndSuggestsGobletSquat() {
        let reps = (1...5).map { rep($0, minKneeAngle: 70, hipBelowKnee: true, torsoLeanDegrees: 60) }

        let result = TechniqueScorer.score(exerciseId: "squat", reps: reps)

        XCTAssertEqual(result.componentScores["torso"], 0)
        XCTAssertEqual(result.substituteExerciseId, "goblet_squat")
        XCTAssertTrue(result.findings.contains { $0.id == "torso_lean_high" })
    }

    func testInconsistentDepthLowersRepeatabilityScore() {
        let consistent = (1...5).map { rep($0, minKneeAngle: 70, hipBelowKnee: true, torsoLeanDegrees: 20) }
        let inconsistent = [
            rep(1, minKneeAngle: 60, hipBelowKnee: true, torsoLeanDegrees: 20),
            rep(2, minKneeAngle: 110, hipBelowKnee: true, torsoLeanDegrees: 20),
            rep(3, minKneeAngle: 65, hipBelowKnee: true, torsoLeanDegrees: 20),
            rep(4, minKneeAngle: 105, hipBelowKnee: true, torsoLeanDegrees: 20),
            rep(5, minKneeAngle: 70, hipBelowKnee: true, torsoLeanDegrees: 20),
        ]

        let consistentResult = TechniqueScorer.score(exerciseId: "squat", reps: consistent)
        let inconsistentResult = TechniqueScorer.score(exerciseId: "squat", reps: inconsistent)

        XCTAssertGreaterThan(consistentResult.componentScores["repeatability"]!,
                            inconsistentResult.componentScores["repeatability"]!)
    }

    func testRushedDescentLowersTempoScore() {
        let controlled = (1...3).map { rep($0, minKneeAngle: 70, hipBelowKnee: true, torsoLeanDegrees: 20, descentSeconds: 3) }
        let rushed = (1...3).map { rep($0, minKneeAngle: 70, hipBelowKnee: true, torsoLeanDegrees: 20, descentSeconds: 0.3) }

        let controlledResult = TechniqueScorer.score(exerciseId: "squat", reps: controlled)
        let rushedResult = TechniqueScorer.score(exerciseId: "squat", reps: rushed)

        XCTAssertEqual(controlledResult.componentScores["tempo"], 100)
        XCTAssertLessThan(rushedResult.componentScores["tempo"]!, 50)
    }

    func testNoRepsProducesZeroScoreNotACrash() {
        let result = TechniqueScorer.score(exerciseId: "squat", reps: [])
        XCTAssertEqual(result.score, 0)
        XCTAssertTrue(result.findings.isEmpty)
    }

    func testWeightsAndThresholdsFromNumbersOverrideDefaults() {
        let weights = TechniqueScorer.Weights.from(["depth": 0.5, "torso": 0.5, "repeatability": 0, "tempo": 0])
        XCTAssertEqual(weights.depth, 0.5)
        XCTAssertEqual(weights.torso, 0.5)

        let thresholds = TechniqueScorer.Thresholds.from(["maxTorsoLeanDegrees": 30])
        XCTAssertEqual(thresholds.maxTorsoLeanDegrees, 30)
        // Untouched keys keep their default.
        XCTAssertEqual(thresholds.minControlledDescentSeconds, TechniqueScorer.Thresholds().minControlledDescentSeconds)
    }
}
