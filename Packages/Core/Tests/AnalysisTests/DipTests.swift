import Contracts
import XCTest
import LiveSet
@testable import Analysis

/// Dips on parallel bars. Three recordings of three different people (side view, parallel bars on a wall ladder,
/// iPhone, Apple Vision poses read once with `VisionPoseExtractor` and thinned to 10 frames/s) pin the behaviour on
/// real people; synthetic dips cover what the recordings do not contain (shallow, no lockout).
final class DipTests: XCTestCase {
    private func clip(_ n: Int) throws -> [PoseFrame] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/dips/dip_clip_\(n).json")
        return try JSONDecoder().decode([PoseFrame].self, from: Data(contentsOf: url))
    }

    // MARK: recorded clips

    /// What a person watching the clip counts: IMG_3025 has 7 dips (the first seconds are the person climbing onto
    /// the bars, which is not a repetition), IMG_3026 has 6 and IMG_3027 has 5.
    private let expectedReps = [3025: 7, 3026: 6, 3027: 5]

    func testRepetitionsInTheRecordedClipsAreCounted() throws {
        for (n, expected) in expectedReps {
            let detection = ClipRepDetector.detect(frames: try clip(n), kind: .dip)
            XCTAssertEqual(detection.reps.count, expected, "IMG_\(n)")
        }
    }

    func testClimbingOntoTheBarsIsNotARepetition() throws {
        // In IMG_3025 the person stands with the hands on the bars for the first 4 seconds, leans, then jumps up.
        let reps = ClipRepDetector.detect(frames: try clip(3025), kind: .dip).reps
        XCTAssertGreaterThan(reps.first?.startTime ?? 0, 4.5)
        let first = try XCTUnwrap(reps.first)
        XCTAssertGreaterThan(MovementKind.dip.primaryAngle(in: first.startFrame) ?? 0, 150, "every counted dip starts locked out")
    }

    func testGoodDipsOfRealPeopleScoreHighWithMeasuredAngles() throws {
        for n in expectedReps.keys {
            let result = TechniqueScorer.score(exerciseId: "dip", kind: .dip, frames: try clip(n))
            XCTAssertGreaterThanOrEqual(result.score, 90, "IMG_\(n)")
            XCTAssertTrue(result.findings.contains { $0.id == "depth_ok" }, "IMG_\(n)")
            XCTAssertTrue(result.findings.contains { $0.id == "lockout_ok" }, "IMG_\(n)")
            XCTAssertFalse(result.findings.contains { $0.id == "dip_shallow" || $0.id == "dip_no_lockout" }, "IMG_\(n)")
            // The bottom of these dips is a bent elbow (about 50-75 degrees) with the shoulder at or below the elbow.
            for rep in ClipRepDetector.detect(frames: try clip(n), kind: .dip).reps {
                let elbow = try XCTUnwrap(MovementKind.dip.primaryAngle(in: rep.bottomFrame))
                XCTAssertTrue((40...90).contains(elbow), "IMG_\(n) rep \(rep.index): \(elbow)")
            }
        }
    }

    func testTheTorsoLeanIsReportedButNotJudged() throws {
        let result = TechniqueScorer.score(exerciseId: "dip", kind: .dip, frames: try clip(3027))
        let lean = try XCTUnwrap(result.findings.first { $0.id == "torso_lean_info" })
        XCTAssertEqual(lean.severity, .good, "the lean is a style, not a mistake")
    }

    func testTheQualityGateAcceptsTheRecordedClips() throws {
        // The fixtures are thinned to 10 frames/s, so the frame rate check is relaxed here; the three full-rate clips
        // (30 frames/s) pass it as well.
        for n in expectedReps.keys {
            let report = QualityGate.assess(frames: try clip(n), kind: .dip, thresholds: QualityGate.Thresholds(minFps: 8))
            XCTAssertTrue(report.passed, "IMG_\(n): \(report.checks.filter { !$0.passed }.map(\.label))")
        }
    }

    func testTheTextsAreWellFormed() throws {
        let result = TechniqueScorer.score(exerciseId: "dip", kind: .dip, frames: try clip(3026))
        for finding in result.findings {
            XCTAssertEqual(finding.detail.filter { $0 == "(" }.count, finding.detail.filter { $0 == ")" }.count, finding.detail)
        }
    }

    // MARK: synthetic dips

    private func simulated(depthFactors: [Double]) -> [PoseFrame] {
        var sim = SimulatedSquat(kind: .dip)
        sim.reps = depthFactors.count
        sim.depthFactors = depthFactors
        sim.eccentricFactors = Array(repeating: 1.0, count: depthFactors.count)
        return sim.frames()
    }

    func testASimulatedFullDipIsFullRangeAndLockedOut() {
        let frames = simulated(depthFactors: [1, 1, 1, 1, 1])
        let detection = ClipRepDetector.detect(frames: frames, kind: .dip)
        XCTAssertEqual(detection.reps.count, 5)
        let result = TechniqueScorer.score(exerciseId: "dip", kind: .dip, frames: frames)
        XCTAssertEqual(result.score, 100)
        let elbow = MovementKind.dip.primaryAngle(in: detection.reps[0].bottomFrame) ?? 0
        XCTAssertEqual(elbow, 73, accuracy: 6, "the simulated bottom is about 73 degrees")
    }

    func testShallowDipsAreFlagged() {
        let result = TechniqueScorer.score(exerciseId: "dip", kind: .dip, frames: simulated(depthFactors: [1, 0.45, 1, 0.45, 0.45]))
        let finding = result.findings.first { $0.id == "dip_shallow" }
        XCTAssertNotNil(finding)
        XCTAssertEqual(finding?.repsAffected, 3)
        XCTAssertLessThan(result.score, 80)
    }

    func testNoLockoutAtTheTopIsFlaggedAndLowersTheScore() {
        let assessor = BasicDipAssessor()
        var sim = SimulatedSquat(kind: .dip)
        sim.reps = 1
        let frames = sim.frames()
        let bottom = frames.min { (MovementKind.dip.primaryAngle(in: $0) ?? 999) < (MovementKind.dip.primaryAngle(in: $1) ?? 999) }!
        // A "top" where the elbows are still bent about 135 degrees.
        let partial = frames.min { abs((MovementKind.dip.primaryAngle(in: $0) ?? 0) - 135) < abs((MovementKind.dip.primaryAngle(in: $1) ?? 0) - 135) ? true : false }!
        let locked = frames[0]
        let good = assessor.assess(bottomFrames: [bottom], startFrames: [locked])
        let bad = assessor.assess(bottomFrames: [bottom], startFrames: [partial])
        XCTAssertEqual(good.score, 100)
        XCTAssertEqual(bad.findings.first { $0.id == "dip_no_lockout" }?.repsAffected, 1)
        XCTAssertEqual(bad.score, 60, "full depth (0.6) without the lockout (0.4)")
    }

    func testAVeryDeepDipIsAnInformationNotAScoreCut() {
        let assessor = BasicDipAssessor()
        var sim = SimulatedSquat(kind: .dip)
        sim.reps = 1
        sim.depthFactors = [1]
        let frames = sim.frames()
        let bottom = frames.min { (MovementKind.dip.primaryAngle(in: $0) ?? 999) < (MovementKind.dip.primaryAngle(in: $1) ?? 999) }!
        // The same dip judged against a stricter "very deep" limit.
        var strict = assessor
        strict.deepElbowAngle = 90
        let result = strict.assess(bottomFrames: [bottom], startFrames: [frames[0]])
        XCTAssertNotNil(result.findings.first { $0.id == "dip_very_deep" })
        XCTAssertEqual(result.score, 100, "a very deep dip is not penalised")
    }

    func testNothingMeasuredMeansNoScore() {
        XCTAssertNil(BasicDipAssessor().assess(bottomFrames: []).score)
        XCTAssertNil(BasicDipAssessor().assess(bottomFrames: [PoseFrame(time: 0, joints: [])]).score)
    }

    func testTheCatalogDipMapsToTheDipMovement() throws {
        let json = #"{"id":"dip","name":"Dipy na poręczach","muscleGroup":"x","equipment":"gym","level":"intermediate","summary":"s","videoURL":null,"substituteIds":[],"supportsAnalysis":true,"pattern":"push","movementTags":[],"timed":false}"#
        let item = try JSONDecoder().decode(ExerciseItem.self, from: Data(json.utf8))
        XCTAssertEqual(MovementKind.kind(for: item), .dip)
        var bench = item
        bench.id = "bench_dip"
        XCTAssertEqual(MovementKind.kind(for: bench), .dip)
        var pushup = item
        pushup.id = "pushup"
        XCTAssertEqual(MovementKind.kind(for: pushup), .pushup)
        var hip = item
        hip.id = "hip_thrust"
        hip.pattern = "hinge"
        XCTAssertNil(MovementKind.kind(for: hip))
    }
}
