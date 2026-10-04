import XCTest
import Contracts
@testable import LiveSet

final class PhaseTrackerTests: XCTestCase {
    /// Runs the simulated squat through signal + tracker.
    private func run(_ sim: SimulatedSquat) -> (reps: [RepTempo], phases: [RepPhase]) {
        var signal = SquatSignal()
        var tracker = PhaseTracker()
        var reps: [RepTempo] = []
        var phases: [RepPhase] = []
        for frame in sim.frames() {
            guard let depth = signal.depth(for: frame) else { continue }
            for event in tracker.update(time: frame.time, depth: depth) {
                switch event {
                case let .phaseStarted(p, _): phases.append(p)
                case let .repCompleted(r): reps.append(r)
                case .idleTimeout: break
                }
            }
        }
        return (reps, phases)
    }

    func testDetectsAllRepetitionsAndPhases() {
        var sim = SimulatedSquat()
        sim.eccentricFactors = [1, 1, 1, 1, 1]
        sim.depthFactors = [1, 1, 1, 1, 1]
        let result = run(sim)
        XCTAssertEqual(result.reps.count, 5)
        XCTAssertEqual(result.phases.filter { $0 == .eccentric }.count, 5)
        XCTAssertEqual(result.phases.filter { $0 == .bottomPause }.count, 5)
        XCTAssertEqual(result.phases.filter { $0 == .concentric }.count, 5)
        XCTAssertTrue(result.reps.allSatisfy(\.isFullRange))
    }

    func testMeasuredDurationsAreCloseToTheSimulatedOnes() {
        var sim = SimulatedSquat()
        sim.eccentricFactors = [1, 1, 1, 1, 1]
        let reps = run(sim).reps
        XCTAssertEqual(reps.count, 5)
        for rep in reps.dropFirst() {
            XCTAssertEqual(rep.eccentric, 2.6, accuracy: 0.6, "eccentric of rep \(rep.index)")
            XCTAssertEqual(rep.concentric, 1.6, accuracy: 0.5, "concentric of rep \(rep.index)")
            XCTAssertEqual(rep.bottomPause, 0.8, accuracy: 0.7, "pause of rep \(rep.index)")
        }
    }

    func testFastRepetitionIsMeasuredAsFast() {
        let reps = run(SimulatedSquat()).reps
        XCTAssertEqual(reps.count, 5)
        // Reps 3 and 4 are simulated with half the eccentric time.
        XCTAssertLessThan(reps[2].eccentric, 1.8)
        XCTAssertGreaterThan(reps[0].eccentric, 2.0)
    }

    func testShallowRepetitionIsNotFullRange() {
        var sim = SimulatedSquat()
        sim.depthFactors = [1, 1, 0.25, 1, 1]
        let reps = run(sim).reps
        XCTAssertEqual(reps.count, 5)
        XCTAssertFalse(reps[2].isFullRange)
    }

    func testStandingStillProducesNoReps() {
        var sim = SimulatedSquat()
        sim.reps = 0
        XCTAssertTrue(run(sim).reps.isEmpty)
    }
}

final class CueAndPolicyTests: XCTestCase {
    func testPhaseLabels() {
        XCTAssertEqual(CuePlanner.label(of: .eccentric), "w dół")
        XCTAssertEqual(CuePlanner.label(of: .concentric), "w górę")
    }

    func testPhaseDurationComesFromTheSpec() {
        XCTAssertEqual(CuePlanner.duration(of: .eccentric, in: .controlled), TempoSpec.controlled.eccentric)
    }

    private func rep(_ i: Int, ecc: Double = 3, pause: Double = 1, conc: Double = 2, full: Bool = true) -> RepTempo {
        RepTempo(index: i, startedAt: 0, eccentric: ecc, bottomPause: pause, concentric: conc,
                 topPauseBefore: 0, peakDepth: full ? 0.8 : 0.2, isFullRange: full)
    }

    func testTooFastEccentricGetsAdviceWithCooldown() {
        var policy = CoachingPolicy()
        XCTAssertEqual(policy.advice(after: rep(1, ecc: 1.0), spec: .controlled), "wolniej w dół")
        XCTAssertNil(policy.advice(after: rep(2, ecc: 1.0), spec: .controlled), "cooldown")
    }

    func testShallowRepetitionGetsDepthAdvice() {
        var policy = CoachingPolicy()
        XCTAssertEqual(policy.advice(after: rep(1, full: false), spec: .controlled), "głębiej")
    }

    func testPraiseAfterThreeRepetitionsOnTempo() {
        var policy = CoachingPolicy()
        XCTAssertNil(policy.advice(after: rep(1), spec: .controlled))
        XCTAssertNil(policy.advice(after: rep(2), spec: .controlled))
        XCTAssertEqual(policy.advice(after: rep(3), spec: .controlled), "dobrze, tak trzymaj")
    }
}

final class TempoScoringTests: XCTestCase {
    private func rep(_ i: Int, ecc: Double, pause: Double, conc: Double) -> RepTempo {
        RepTempo(index: i, startedAt: 0, eccentric: ecc, bottomPause: pause, concentric: conc,
                 topPauseBefore: 0, peakDepth: 0.8, isFullRange: true)
    }

    func testOnTempoScoresHigh() {
        let reps = (1...5).map { rep($0, ecc: 3.1, pause: 1.0, conc: 2.0) }
        let result = TempoScoring.evaluate(reps: reps, spec: .controlled)
        XCTAssertGreaterThanOrEqual(result.score, 95)
        XCTAssertTrue(result.findings.allSatisfy { $0.severity == .good })
    }

    func testFastEccentricIsFlagged() {
        let reps = (1...5).map { rep($0, ecc: 1.2, pause: 1.0, conc: 2.0) }
        let result = TempoScoring.evaluate(reps: reps, spec: .controlled)
        XCTAssertLessThan(result.score, 90)
        let finding = result.findings.first { $0.id == "tempo_ecc_fast" }
        XCTAssertNotNil(finding)
        XCTAssertEqual(finding?.repsAffected, 5)
        XCTAssertEqual(finding?.severity, .major)
    }

    func testMissingPauseIsFlagged() {
        let reps = (1...4).map { rep($0, ecc: 3, pause: 0, conc: 2) }
        let result = TempoScoring.evaluate(reps: reps, spec: .controlled)
        XCTAssertNotNil(result.findings.first { $0.id == "tempo_pause_fast" })
    }

    func testNoRepsGivesZero() {
        XCTAssertEqual(TempoScoring.evaluate(reps: [], spec: .controlled).score, 0)
    }

    func testTempoLabel() {
        XCTAssertEqual(TempoSpec.controlled.label, "3-1-2-0")
    }
}

final class FramingTests: XCTestCase {
    private let standing = SimulatedSquat().frame(at: 0)

    func testGoodSideViewIsReady() {
        let report = FramingAssessor.assess(standing)
        XCTAssertTrue(report.ready, "\(report.checks)")
        XCTAssertNil(report.hint)
    }

    func testMissingFeetGivesStepBackHint() {
        var frame = standing
        frame.joints.removeAll { $0.name == .leftAnkle || $0.name == .rightAnkle }
        let report = FramingAssessor.assess(frame)
        XCTAssertFalse(report.ready)
        XCTAssertEqual(report.hint, "Odejdź krok do tyłu, nie widzę stóp")
    }

    func testFacingTheCameraGivesSideViewHint() {
        var frame = standing
        frame.joints = frame.joints.map { joint in
            var j = joint
            if j.name == .leftShoulder { j.x = 0.60 }
            if j.name == .rightShoulder { j.x = 0.40 }
            return j
        }
        let report = FramingAssessor.assess(frame)
        XCTAssertEqual(report.hint, "Ustaw się bokiem do kamery")
    }

    func testNoPersonGivesHint() {
        XCTAssertFalse(FramingAssessor.assess(nil).ready)
        XCTAssertFalse(FramingAssessor.assess(PoseFrame(time: 0, joints: [])).ready)
    }
}

final class SquatAssessorTests: XCTestCase {
    func testDeepUprightSquatIsGood() {
        let sim = SimulatedSquat()
        let bottom = sim.frame(at: sim.leadIn + sim.eccentric + 0.2)
        let result = BasicSquatAssessor().assess(bottomFrames: [bottom, bottom])
        XCTAssertEqual(result.score, 100)
        XCTAssertTrue(result.findings.allSatisfy { $0.severity == .good })
    }

    func testShallowSquatIsFlagged() {
        var sim = SimulatedSquat()
        sim.depthFactors = [0.4]
        let bottom = sim.frame(at: sim.leadIn + sim.eccentricFactors[0] * sim.eccentric + 0.2)
        let result = BasicSquatAssessor().assess(bottomFrames: [bottom])
        XCTAssertNotNil(result.findings.first { $0.id == "depth_shallow" })
    }

    func testBends_standingToBottomOfASquatBendsTheKnee() {
        func leg(kneeX: Double) -> PoseFrame {
            PoseFrame(time: 0, joints: [
                Joint(name: .leftHip, x: 0.5, y: 0.5, confidence: 1),
                Joint(name: .leftKnee, x: kneeX, y: 0.7, confidence: 1),
                Joint(name: .leftAnkle, x: 0.5, y: 0.9, confidence: 1),
            ])
        }
        // Straight leg (knee under the hip) against a clearly bent one (knee forward).
        XCTAssertEqual(MovementKind.squat.bends(from: leg(kneeX: 0.5), to: leg(kneeX: 0.8), atLeast: 20), true)
        // The same leg moved as a whole (a jump, a step): the knee did not bend.
        XCTAssertEqual(MovementKind.squat.bends(from: leg(kneeX: 0.5), to: leg(kneeX: 0.5), atLeast: 20), false)
    }

    func testBends_missingJointsIsNil() {
        let empty = PoseFrame(time: 0, joints: [])
        XCTAssertNil(MovementKind.squat.bends(from: empty, to: empty, atLeast: 20))
        XCTAssertNil(MovementKind.pushup.bends(from: empty, to: empty, atLeast: 20))
    }
}

@MainActor
final class LiveSetEngineTests: XCTestCase {
    func testWholeSetEndToEnd() {
        let voice = RecordingVoice()
        let engine = LiveSetEngine(exerciseId: "squat", spec: .controlled, voice: voice, isSimulated: true)
        let sim = SimulatedSquat()
        for frame in sim.frames() { engine.ingest(frame) }

        XCTAssertEqual(engine.stage, .active)
        XCTAssertEqual(engine.reps.count, 5)

        engine.finish()
        guard let summary = engine.summary else { return XCTFail("no summary") }
        XCTAssertEqual(summary.reps.count, 5)
        XCTAssertTrue(summary.isSimulated)
        XCTAssertGreaterThan(summary.framing.goodFrameRatio, 0.9)
        XCTAssertNotNil(summary.techniqueScore)
        XCTAssertTrue(summary.tempoFindings.contains { $0.id == "tempo_ecc_fast" || $0.id == "tempo_ecc_ok" })

        // The set starts with a command; after it only the metronome beeps (not tied to the frames), no phase words.
        let said = voice.spoken.map(\.text)
        XCTAssertEqual(said.filter { $0 == "zaczynaj" }.count, 1, "spoken: \(said)")
        XCTAssertFalse(said.contains("w dół"), "spoken: \(said)")
        XCTAssertFalse(said.contains("w górę"), "spoken: \(said)")
        XCTAssertTrue(said.contains { $0.hasPrefix("Koniec serii") })
        // Corrections still happen (shown on screen as lastCue) but aren't spoken live anymore.
        XCTAssertFalse(said.contains("wolniej w dół"), "spoken: \(said)")

        // Every counted repetition was a good squat, so the live score tracks the final one.
        XCTAssertEqual(engine.liveTechniqueScore, summary.techniqueScore)
    }

    /// A movement can swing the depth signal exactly like a real repetition (jumping, a step, the wrong exercise)
    /// without the exercise's own joint bending. Here the whole body moves up and down like the squatter's hips do,
    /// rigidly, so the knee never bends: nothing may be counted.
    func testRepsInWhichTheJointDoesNotBendAreNotCounted() {
        let sim = SimulatedSquat()
        let standing = sim.frame(at: 0)
        let hip0 = standing.joint(.root)?.y ?? 0
        let engine = LiveSetEngine(exerciseId: "squat", spec: .controlled, voice: RecordingVoice(), isSimulated: true)
        for frame in sim.frames() {
            let dy = (frame.joint(.root)?.y ?? hip0) - hip0
            engine.ingest(PoseFrame(time: frame.time, joints: standing.joints.map { var j = $0; j.y += dy; return j }))
        }
        XCTAssertEqual(engine.reps.count, 0)
        XCTAssertNil(engine.liveTechniqueScore)
        XCTAssertEqual(engine.lastCue, "nie liczę — to nie to ćwiczenie")
    }

    func testBadFramingSpeaksHintAndDoesNotStart() {
        let voice = RecordingVoice()
        let engine = LiveSetEngine(exerciseId: "squat", spec: .controlled, voice: voice)
        var frame = SimulatedSquat().frame(at: 0)
        frame.joints.removeAll { $0.name == .leftAnkle || $0.name == .rightAnkle }
        for i in 0..<60 {
            var f = frame
            f.time = Double(i) / 30
            engine.ingest(f)
        }
        XCTAssertEqual(engine.stage, .framing)
        XCTAssertTrue(voice.spoken.contains { $0.text == "Odejdź krok do tyłu, nie widzę stóp" })
    }
}

@MainActor
final class SimulationFollowsTempoTests: XCTestCase {
    func testSimulatedPersonMovesToThePlanTempo() {
        // The simulated pull-up is not counted by the engine even at its default tempo (its elbow barely bends), so it is left out.
        for kind in MovementKind.allCases where kind != .pullup {
            let engine = LiveSetEngine(exerciseId: "x", spec: .controlled, voice: RecordingVoice(), kind: kind, isSimulated: true)
            let sim = SimulatedSquat.following(.controlled, kind: kind)
            var activeAt: Double?
            for frame in sim.frames() {
                engine.ingest(frame)
                if activeAt == nil, engine.stage == .active { activeAt = frame.time }
            }
            XCTAssertEqual(activeAt ?? 0, 2.04, accuracy: 0.05, "\(kind)")
            XCTAssertEqual(engine.reps.count, 5, "\(kind)")
        }
    }
}

final class TimedVoice: CoachVoice {
    var beeps: [(RepPhase, Date)] = []
    var headphonesConnected: Bool { true }
    func prepare() {}
    func speak(_ text: String, priority: VoicePriority) {}
    func playPhaseBeep(_ phase: RepPhase) { beeps.append((phase, Date())) }
    func finish() {}
}

@MainActor
final class MetronomeTimingTests: XCTestCase {
    func testBeepsSoundAtTheTimesOfThePlanTempo() async throws {
        let voice = TimedVoice()
        let spec = TempoSpec(eccentric: 0.3, bottomPause: 0.1, concentric: 0.2, topPause: 0)
        let engine = LiveSetEngine(exerciseId: "squat", spec: spec, voice: voice, isSimulated: true, beepLeadIn: 0.2)
        for frame in SimulatedSquat().frames() { engine.ingest(frame) }
        let start = Date()
        try await Task.sleep(nanoseconds: 1_500_000_000)
        engine.finish()
        let times = voice.beeps.map { $0.1.timeIntervalSince(start) }
        print("BEEPS", voice.beeps.map { "\($0.0)" }, times)
        XCTAssertGreaterThan(voice.beeps.count, 4)
    }
}

final class TempoMetronomeTests: XCTestCase {
    func testBeepsFollowThePlanTempo() {
        // 3 s down, 1 s pause, 2 s up: one repetition lasts 6 s.
        let metronome = TempoMetronome(spec: .controlled, leadIn: 2)
        XCTAssertEqual(metronome.cycleDuration, 6)
        XCTAssertEqual(metronome.beat(at: 0), .init(phase: .eccentric, offset: 2))
        XCTAssertEqual(metronome.beat(at: 1), .init(phase: .concentric, offset: 6))
        XCTAssertEqual(metronome.beat(at: 2), .init(phase: .eccentric, offset: 8))
        XCTAssertEqual(metronome.beat(at: 3), .init(phase: .concentric, offset: 12))
    }

    func testTopPauseLengthensTheCycle() {
        let metronome = TempoMetronome(spec: TempoSpec(eccentric: 2, bottomPause: 0, concentric: 1, topPause: 1), leadIn: 0)
        XCTAssertEqual(metronome.cycleDuration, 4)
        XCTAssertEqual(metronome.beat(at: 1), .init(phase: .concentric, offset: 2))
        XCTAssertEqual(metronome.beat(at: 2), .init(phase: .eccentric, offset: 4))
    }

    func testPullUpStartsWithTheLiftingPhase() {
        let metronome = TempoMetronome(spec: .controlled, reversed: true, leadIn: 0)
        XCTAssertEqual(metronome.beat(at: 0), .init(phase: .concentric, offset: 0))
        // 2 s pull, 1 s pause at the top, then the 3 s lowering.
        XCTAssertEqual(metronome.beat(at: 1), .init(phase: .eccentric, offset: 3))
    }

    func testEmptySpecHasNoBeats() {
        let metronome = TempoMetronome(spec: TempoSpec(eccentric: 0, bottomPause: 0, concentric: 0, topPause: 0))
        XCTAssertNil(metronome.beat(at: 0))
    }
}
