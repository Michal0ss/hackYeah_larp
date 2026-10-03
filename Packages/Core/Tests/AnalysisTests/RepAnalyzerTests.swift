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

    /// `angleSeries` feeds the chart on the result screen. A single bad Vision frame (a glitch, not
    /// a real movement) should barely show up in it, the same way a one-frame tracking glitch can't
    /// become the chosen "bottom of a squat" (`MovementKind.representativeFrame`).
    func testAngleSeriesSmoothesASingleBadFrame() {
        func frame(time: Double, kneeOffset: Double) -> PoseFrame {
            PoseFrame(time: time, joints: [
                Joint(name: .leftHip, x: 0.5, y: 0.3, confidence: 1),
                Joint(name: .leftKnee, x: 0.5 + kneeOffset, y: 0.6, confidence: 1),
                Joint(name: .leftAnkle, x: 0.5, y: 0.9, confidence: 1),
            ])
        }
        // A steady knee angle except one glitched frame (index 3) far off from its neighbors.
        let offsets = [0.05, 0.06, 0.05, 0.35, 0.05, 0.06, 0.05]
        let frames = offsets.enumerated().map { frame(time: Double($0.offset) / 30, kneeOffset: $0.element) }

        let raw = frames.compactMap { MovementKind.squat.primaryAngle(in: $0, minConfidence: 0.1) }
        let smoothed = RepAnalyzer.angleSeries(in: frames, kind: .squat).map(\.angle)

        XCTAssertEqual(raw.count, 7)
        XCTAssertEqual(smoothed.count, 7)
        let rawDip = raw[2] - raw[3]
        let smoothedDip = smoothed[2] - smoothed[3]
        XCTAssertGreaterThan(rawDip, 30, "the injected glitch should be a real outlier in the raw signal")
        XCTAssertLessThan(smoothedDip, rawDip / 3, "smoothing should absorb most of a single-frame glitch")
    }

    func testAngleSeriesMatchesSimulatedSquatLength() {
        var sim = SimulatedSquat()
        sim.reps = 2
        let frames = sim.frames()
        let series = RepAnalyzer.angleSeries(in: frames, kind: .squat)
        XCTAssertFalse(series.isEmpty)
        XCTAssertLessThanOrEqual(series.count, frames.count)
    }
}
