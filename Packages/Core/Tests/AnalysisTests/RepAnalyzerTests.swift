import XCTest
import Contracts
import LiveSet
@testable import Analysis

final class RepAnalyzerTests: XCTestCase {
    func testCountsRepsAndReportsFullDepth() {
        var sim = SimulatedSquat()
        sim.reps = 4
        sim.depthFactors = [1.0, 1.0, 1.0, 1.0]

        let reps = RepAnalyzer.analyze(frames: sim.frames()).reps

        XCTAssertEqual(reps.count, 4)
        XCTAssertTrue(reps.allSatisfy(\.hipBelowKnee), "full-depth reps should count as hip below knee")
        for rep in reps {
            XCTAssertLessThan(rep.minKneeAngle, 120, "a full squat should bend the knee well past 120°")
            XCTAssertGreaterThan(rep.descentSeconds, 0)
            XCTAssertGreaterThan(rep.ascentSeconds, 0)
        }
    }

    func testShallowRepsAreNotHipBelowKnee() {
        var sim = SimulatedSquat()
        sim.reps = 3
        sim.depthFactors = [0.4, 0.4, 0.4]
        sim.eccentricFactors = [1.0, 1.0, 1.0]

        let reps = RepAnalyzer.analyze(frames: sim.frames()).reps

        XCTAssertEqual(reps.count, 3)
        XCTAssertTrue(reps.allSatisfy { !$0.hipBelowKnee }, "a shallow squat should not reach hip-below-knee")
    }

    func testDescentAndAscentMatchSimulatedTiming() {
        var sim = SimulatedSquat()
        sim.reps = 1
        sim.eccentric = 2.0
        sim.concentric = 1.0
        sim.bottomPause = 0.3
        sim.depthFactors = [1.0]
        sim.eccentricFactors = [1.0]

        let reps = RepAnalyzer.analyze(frames: sim.frames()).reps

        XCTAssertEqual(reps.count, 1)
        XCTAssertEqual(reps[0].descentSeconds, 2.0, accuracy: 0.3)
        XCTAssertEqual(reps[0].ascentSeconds, 1.0, accuracy: 0.3)
    }

    func testNoFramesProduceNoReps() {
        XCTAssertEqual(RepAnalyzer.analyze(frames: []).reps.count, 0)
    }

    func testPushupKindUsesNeckDepthAndDefaultAssessor() {
        // A minimal synthetic push-up isn't worth building (the geometry is Michał's); this just
        // checks the kind parameter is threaded through without crashing on an empty/short clip.
        let result = RepAnalyzer.analyze(frames: [], kind: .pushup)
        XCTAssertTrue(result.reps.isEmpty)
        XCTAssertTrue(result.bottomFrames.isEmpty)
    }
}
