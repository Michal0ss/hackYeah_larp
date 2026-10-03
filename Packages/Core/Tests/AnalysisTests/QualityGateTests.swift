import XCTest
import Contracts
import LiveSet
@testable import Analysis

final class QualityGateTests: XCTestCase {
    private func goodFrames() -> [PoseFrame] {
        var sim = SimulatedSquat()
        sim.reps = 5
        return sim.frames()
    }

    /// Shrinks every joint toward the frame center, simulating a person standing too far away.
    private func shrunk(_ frames: [PoseFrame], scale: Double) -> [PoseFrame] {
        frames.map { frame in
            var copy = frame
            copy.joints = frame.joints.map { joint in
                var j = joint
                j.x = 0.5 + (joint.x - 0.5) * scale
                j.y = 0.5 + (joint.y - 0.5) * scale
                return j
            }
            return copy
        }
    }

    func testGoodRecordingPasses() {
        let report = QualityGate.assess(frames: goodFrames())
        XCTAssertTrue(report.passed, "expected all checks to pass, got: \(report.checks)")
        XCTAssertNil(report.userHint)
    }

    func testTooFewRepsFails() {
        var sim = SimulatedSquat()
        sim.reps = 2
        sim.depthFactors = [1.0, 1.0]
        sim.eccentricFactors = [1.0, 1.0]

        let report = QualityGate.assess(frames: sim.frames())

        XCTAssertFalse(report.passed)
        let repsCheck = report.checks.first { $0.id == "rep_count" }
        XCTAssertEqual(repsCheck?.passed, false)
        XCTAssertNotNil(report.userHint)
    }

    func testPersonTooSmallInFrameFails() {
        let report = QualityGate.assess(frames: shrunk(goodFrames(), scale: 0.3))

        XCTAssertFalse(report.passed)
        let sizeCheck = report.checks.first { $0.id == "size" }
        XCTAssertEqual(sizeCheck?.passed, false)
    }

    func testMultiplePeopleInFrameFails() {
        let crowded = goodFrames().map { frame -> PoseFrame in
            var copy = frame
            copy.peopleDetected = 2
            return copy
        }

        let report = QualityGate.assess(frames: crowded)

        XCTAssertFalse(report.passed)
        let peopleCheck = report.checks.first { $0.id == "single_person" }
        XCTAssertEqual(peopleCheck?.passed, false)
    }

    func testLowFrameRateFails() {
        // Every 3rd frame of a 30 fps simulation: effectively ~10 fps, well under the minimum.
        let sparse = goodFrames().enumerated().compactMap { index, frame in index % 3 == 0 ? frame : nil }

        let report = QualityGate.assess(frames: sparse)

        let fpsCheck = report.checks.first { $0.id == "fps" }
        XCTAssertEqual(fpsCheck?.passed, false)
    }

    func testThresholdsFromNumbersOverridesDefaults() {
        let thresholds = QualityGate.Thresholds.from(["minReps": 1, "minFps": 5])
        XCTAssertEqual(thresholds.minReps, 1)
        XCTAssertEqual(thresholds.minFps, 5)
        // Untouched keys keep their default.
        XCTAssertEqual(thresholds.maxPeople, QualityGate.Thresholds().maxPeople)
    }
}
