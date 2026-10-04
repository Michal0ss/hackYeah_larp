import XCTest
import Contracts
@testable import LiveSet

final class TechniqueContextTests: XCTestCase {
    private let base = AngleReference()
    private let rules = ContextRules()

    // MARK: Helpers

    /// A side-view squat at its lowest point: the thigh runs forward from the hip, the torso leans `leanDegrees` from the
    /// vertical. `thighToTorso` sets the proportion, `hipAboveKnee` how far the hip stays above the knee line.
    private func squatFrame(time: Double = 0, thighToTorso: Double = 0.85, leanDegrees: Double = 30,
                            hipAboveKnee: Double = 0, aspect: Double? = nil) -> PoseFrame {
        let torso = 0.30
        let lean = leanDegrees * .pi / 180
        let hip = (x: 0.45, y: 0.60)
        let neck = (x: hip.x + sin(lean) * torso, y: hip.y - cos(lean) * torso)
        let knee = (x: hip.x + thighToTorso * torso, y: hip.y + hipAboveKnee)
        let ankle = (x: knee.x - 0.03, y: knee.y + 0.25)
        func joint(_ name: JointName, _ point: (x: Double, y: Double), _ confidence: Double = 0.9) -> Joint {
            Joint(name: name, x: point.x, y: point.y, confidence: confidence)
        }
        return PoseFrame(time: time, joints: [
            joint(.neck, neck), joint(.root, hip), joint(.leftHip, hip), joint(.leftKnee, knee), joint(.leftAnkle, ankle),
        ], aspect: aspect)
    }

    private func findingIds(_ assessment: TechniqueAssessment) -> Set<String> {
        Set(assessment.findings.map(\.id))
    }

    // MARK: Standard context

    func testStandardContextChangesNothing() {
        for kind in MovementKind.allCases {
            let adjustment = TechniqueContext.standard.adjustment(for: kind, base: base, rules: rules)
            XCTAssertEqual(adjustment.reference, base, "\(kind)")
            XCTAssertEqual(adjustment.torsoLeanExtra, 0)
            XCTAssertEqual(adjustment.repeatabilityExtra, 0)
            XCTAssertTrue(adjustment.isStandard)
            XCTAssertTrue(adjustment.notes.isEmpty)
        }
    }

    func testGoodMobilityNeverNarrowsTheStandard() {
        let context = TechniqueContext(lowerBodyMobility: .good, shoulderMobility: .good)
        for kind in MovementKind.allCases {
            XCTAssertEqual(context.adjustment(for: kind, base: base, rules: rules).reference, base, "\(kind)")
        }
    }

    // MARK: Squat

    func testLimitedLowerBodyMobilityWidensTheSquat() {
        let context = TechniqueContext(lowerBodyMobility: .limited)
        let adjustment = context.adjustment(for: .squat, base: base, rules: rules)
        XCTAssertEqual(adjustment.reference.squatKneeParallelMax, base.squatKneeParallelMax + 12)
        XCTAssertEqual(adjustment.reference.squatKneeDeepMax, base.squatKneeDeepMax + 12)
        XCTAssertEqual(adjustment.reference.squatDepthTolerance, base.squatDepthTolerance + 0.02, accuracy: 1e-9)
        XCTAssertEqual(adjustment.reference.squatTorsoLeanMax, base.squatTorsoLeanMax + 5)
        XCTAssertEqual(adjustment.torsoLeanExtra, 5)
        XCTAssertEqual(adjustment.notes.count, 1)
        XCTAssertFalse(adjustment.isStandard)
        // The band that the live readout shows moves up with the limit.
        XCTAssertEqual(MovementKind.squat.targetBand(adjustment.reference).upperBound, base.squatKneeParallelMax + 12)
    }

    func testSquatAllowancesAreCappedWhenReasonsAdd() {
        let context = TechniqueContext(lowerBodyMobility: .limited, level: .beginner, lowerBodyCaution: true)
        let adjustment = context.adjustment(for: .squat, base: base, rules: rules)
        XCTAssertEqual(adjustment.reference.squatKneeParallelMax, base.squatKneeParallelMax + 20, "12 + 12 capped at 20")
        XCTAssertEqual(adjustment.reference.squatDepthTolerance, base.squatDepthTolerance + 0.04, accuracy: 1e-9)
        XCTAssertEqual(adjustment.torsoLeanExtra, 8, "5 + 3 capped at 8")
        XCTAssertEqual(adjustment.repeatabilityExtra, 5)
        XCTAssertEqual(adjustment.notes.count, 3)
    }

    func testBeginnerWidensEveryExerciseALittle() {
        let context = TechniqueContext(level: .beginner)
        let squat = context.adjustment(for: .squat, base: base, rules: rules)
        XCTAssertEqual(squat.reference.squatDepthTolerance, base.squatDepthTolerance + 0.01, accuracy: 1e-9)
        XCTAssertEqual(squat.reference.squatTorsoLeanMax, base.squatTorsoLeanMax + 3)
        XCTAssertEqual(squat.repeatabilityExtra, 5)
        XCTAssertEqual(context.adjustment(for: .pushup, base: base, rules: rules).reference.pushupElbowBottomMax,
                       base.pushupElbowBottomMax + 5)
        XCTAssertEqual(context.adjustment(for: .pullup, base: base, rules: rules).reference.pullupElbowTopMax,
                       base.pullupElbowTopMax + 5)
        XCTAssertEqual(context.adjustment(for: .dip, base: base, rules: rules).reference.dipElbowBottomMax,
                       base.dipElbowBottomMax + 5)
    }

    func testCautionWidensOnlyTheMatchingRegion() {
        let lower = TechniqueContext(lowerBodyCaution: true)
        XCTAssertGreaterThan(lower.adjustment(for: .squat, base: base, rules: rules).reference.squatKneeParallelMax,
                             base.squatKneeParallelMax)
        XCTAssertEqual(lower.adjustment(for: .pushup, base: base, rules: rules).reference, base)
        XCTAssertEqual(lower.adjustment(for: .dip, base: base, rules: rules).reference, base)

        let upper = TechniqueContext(upperBodyCaution: true)
        XCTAssertEqual(upper.adjustment(for: .squat, base: base, rules: rules).reference, base)
        XCTAssertEqual(upper.adjustment(for: .pushup, base: base, rules: rules).reference.pushupElbowBottomMax,
                       base.pushupElbowBottomMax + 10)
        XCTAssertEqual(upper.adjustment(for: .pullup, base: base, rules: rules).reference.pullupElbowTopMax,
                       base.pullupElbowTopMax + 10)
        XCTAssertEqual(upper.adjustment(for: .dip, base: base, rules: rules).reference.dipElbowBottomMax,
                       base.dipElbowBottomMax + 10)
    }

    func testCautionDoesNotLoosenTheTorsoLimit() {
        // A forward lean is not made easier for a person with an injury: only the depth is relaxed.
        let adjustment = TechniqueContext(lowerBodyCaution: true).adjustment(for: .squat, base: base, rules: rules)
        XCTAssertEqual(adjustment.reference.squatTorsoLeanMax, base.squatTorsoLeanMax)
        XCTAssertEqual(adjustment.torsoLeanExtra, 0)
    }

    // MARK: Upper body

    func testShoulderMobilityOnlyAffectsDips() {
        let context = TechniqueContext(shoulderMobility: .limited)
        XCTAssertEqual(context.adjustment(for: .dip, base: base, rules: rules).reference.dipElbowBottomMax,
                       base.dipElbowBottomMax + 10)
        XCTAssertEqual(context.adjustment(for: .pushup, base: base, rules: rules).reference, base)
        XCTAssertEqual(context.adjustment(for: .pullup, base: base, rules: rules).reference, base)
        XCTAssertEqual(context.adjustment(for: .squat, base: base, rules: rules).reference, base)
    }

    func testElbowAllowancesAreCapped() {
        let context = TechniqueContext(shoulderMobility: .limited, level: .beginner, upperBodyCaution: true)
        // 5 + 10 + 10 = 25, capped at 15.
        XCTAssertEqual(context.adjustment(for: .dip, base: base, rules: rules).reference.dipElbowBottomMax,
                       base.dipElbowBottomMax + 15)
    }

    func testPullupBandFollowsTheWiderLimit() {
        let adjustment = TechniqueContext(level: .beginner).adjustment(for: .pullup, base: base, rules: rules)
        XCTAssertEqual(MovementKind.pullup.targetBand(adjustment.reference).upperBound, base.pullupElbowTopMax + 5)
    }

    // MARK: Proportions

    func testLongThighsWidenTheTorsoLimitOnlyAboveTheReference() {
        func extra(_ ratio: Double) -> Double {
            TechniqueContext.standard.adjustment(for: .squat, base: base, rules: rules, thighToTorso: ratio).torsoLeanExtra
        }
        XCTAssertEqual(extra(0.95), 6, accuracy: 1e-9, "(0.95 - 0.85) x 60")
        XCTAssertEqual(extra(0.85), 0)
        XCTAssertEqual(extra(0.70), 0, "short thighs never make the limit stricter")
        XCTAssertEqual(extra(1.30), 8, "capped")
    }

    func testProportionNoteAppearsOnlyWhenItMatters() {
        let long = TechniqueContext.standard.adjustment(for: .squat, base: base, rules: rules, thighToTorso: 0.95)
        XCTAssertTrue(long.notes.contains { $0.contains("proporcje") })
        let near = TechniqueContext.standard.adjustment(for: .squat, base: base, rules: rules, thighToTorso: 0.86)
        XCTAssertTrue(near.notes.isEmpty, "0.6 degrees is not worth a sentence")
        XCTAssertTrue(TechniqueContext.standard.adjustment(for: .pushup, base: base, rules: rules, thighToTorso: 1.2).isStandard)
    }

    func testProportionsAddToTheContextAllowance() {
        let context = TechniqueContext(lowerBodyMobility: .limited)
        let adjustment = context.adjustment(for: .squat, base: base, rules: rules, thighToTorso: 0.95)
        XCTAssertEqual(adjustment.torsoLeanExtra, 5 + 6, accuracy: 1e-9)
        XCTAssertEqual(adjustment.reference.squatTorsoLeanMax, base.squatTorsoLeanMax + 11, accuracy: 1e-9)
    }

    // MARK: Rules from config

    func testRulesFromConfigIgnoreNegativeValuesAndKeepMissingOnes() {
        let rules = ContextRules(values: ["kneeExtraLimited": -5, "elbowExtraBeginner": 7, "thighToTorsoReference": 0.9])
        XCTAssertEqual(rules.kneeExtraLimited, 0, "a negative value would narrow: ignored")
        XCTAssertEqual(rules.elbowExtraBeginner, 7)
        XCTAssertEqual(rules.thighToTorsoReference, 0.9)
        XCTAssertEqual(rules.kneeExtraCaution, ContextRules().kneeExtraCaution)
        XCTAssertEqual(ContextRules(values: [:]), ContextRules())
    }

    // MARK: Measuring proportions

    func testThighToTorsoIsTheMedianOfTheFrames() {
        let frames = [0.80, 0.85, 0.90, 0.95, 1.00].map { squatFrame(thighToTorso: $0) }
        XCTAssertEqual(BodyProportions.thighToTorso(in: frames) ?? 0, 0.90, accuracy: 1e-6)
    }

    func testTrackingGlitchesAndSparseFramesAreNotMeasured() {
        let good = [0.85, 0.85, 0.85].map { squatFrame(thighToTorso: $0) }
        let glitch = squatFrame(thighToTorso: 3.0)
        XCTAssertEqual(BodyProportions.thighToTorso(in: good + [glitch]) ?? 0, 0.85, accuracy: 1e-6, "an impossible ratio is dropped")
        XCTAssertNil(BodyProportions.thighToTorso(in: Array(good.prefix(2))), "two frames are too few")
        XCTAssertNil(BodyProportions.thighToTorso(in: []))
        var unsure = squatFrame(thighToTorso: 0.85)
        unsure.joints = unsure.joints.map { var j = $0; j.confidence = 0.1; return j }
        XCTAssertNil(BodyProportions.thighToTorso(in: [unsure, unsure, unsure]), "joints below the confidence are not used")
    }

    func testProportionsAreMeasuredInImageHeightUnits() {
        // A portrait video (aspect 0.5): the same pose must give the same ratio as in a square image once x is corrected.
        let square = squatFrame(thighToTorso: 0.9, leanDegrees: 0)
        var portrait = square
        portrait.aspect = 0.5
        portrait.joints = square.joints.map { var j = $0; j.x = 0.5 + (j.x - 0.5) * 2; return j }
        let a = BodyProportions.thighToTorso(in: [square, square, square])!
        let b = BodyProportions.thighToTorso(in: [portrait, portrait, portrait])!
        XCTAssertEqual(a, b, accuracy: 1e-6)
    }

    // MARK: The contextual assessor

    func testLongThighsAreNotFlaggedForTheLeanTheyNeed() {
        // 48 degrees is over the standard 45, but a thigh that long needs about that much lean.
        let long = (0..<3).map { squatFrame(time: Double($0), thighToTorso: 0.95, leanDegrees: 48) }
        let standard = BasicSquatAssessor(reference: base).assess(bottomFrames: long)
        XCTAssertTrue(findingIds(standard).contains("torso_lean_high"))

        let assessor = ContextualAssessor(kind: .squat, base: base, context: .standard)
        XCTAssertTrue(findingIds(assessor.assess(bottomFrames: long)).contains("torso_ok"))

        let average = (0..<3).map { squatFrame(time: Double($0), thighToTorso: 0.85, leanDegrees: 48) }
        XCTAssertTrue(findingIds(ContextualAssessor(kind: .squat, base: base, context: .standard)
            .assess(bottomFrames: average)).contains("torso_lean_high"), "average proportions keep the standard limit")
    }

    func testTheAssessorRemembersProportionsAcrossRepetitions() {
        let assessor = ContextualAssessor(kind: .squat, base: base, context: .standard)
        func oneRep(_ t: Double) -> TechniqueAssessment {
            assessor.assess(bottomFrames: [squatFrame(time: t, thighToTorso: 0.95, leanDegrees: 48)],
                            startFrames: [squatFrame(time: t - 1, thighToTorso: 0.95, leanDegrees: 5)])
        }
        // The first repetition gives two frames, too few to measure: the standard limit applies.
        XCTAssertTrue(findingIds(oneRep(1)).contains("torso_lean_high"))
        // From the second repetition on, the set has shown enough.
        XCTAssertTrue(findingIds(oneRep(3)).contains("torso_ok"))
        XCTAssertTrue(findingIds(oneRep(5)).contains("torso_ok"))
    }

    func testLimitedMobilityAcceptsAShallowerSquat() {
        // The hip stays 0.03 of the image height above the knee line: shallow by the standard (0.02), deep enough with
        // the allowance of limited mobility (0.04).
        let frames = (0..<3).map { squatFrame(time: Double($0), hipAboveKnee: 0.03) }
        let standard = ContextualAssessor(kind: .squat, base: base, context: .standard).assess(bottomFrames: frames)
        XCTAssertTrue(findingIds(standard).contains("depth_shallow"))
        let limited = ContextualAssessor(kind: .squat, base: base, context: TechniqueContext(lowerBodyMobility: .limited))
            .assess(bottomFrames: frames)
        XCTAssertTrue(findingIds(limited).contains("depth_ok"))
        XCTAssertGreaterThan(limited.score ?? 0, standard.score ?? 100)
    }

    func testTheAssessorNeverScoresBelowTheStandardOne() {
        // Context only widens, so with any context the score cannot drop under the standard score.
        let frames = (0..<4).map { squatFrame(time: Double($0), thighToTorso: 0.9, leanDegrees: Double(40 + $0 * 4), hipAboveKnee: 0.01 * Double($0)) }
        let standardScore = BasicSquatAssessor(reference: base).assess(bottomFrames: frames).score ?? 0
        let contexts = [
            TechniqueContext(lowerBodyMobility: .limited),
            TechniqueContext(level: .beginner),
            TechniqueContext(lowerBodyCaution: true),
            TechniqueContext(lowerBodyMobility: .limited, level: .beginner, lowerBodyCaution: true),
            TechniqueContext(lowerBodyMobility: .good),
        ]
        for context in contexts {
            let score = ContextualAssessor(kind: .squat, base: base, context: context).assess(bottomFrames: frames).score ?? 0
            XCTAssertGreaterThanOrEqual(score, standardScore, "\(context)")
        }
    }

    func testTheAssessorWorksForTheOtherExercisesToo() {
        // No proportions play a part for a push-up; with the standard context it equals the plain assessor.
        let frames = (0..<5).map { SimulatedSquat(kind: .pushup).frame(at: Double($0) * 0.5) }
        let plain = MovementKind.pushup.assessor(reference: base).assess(bottomFrames: frames, startFrames: frames)
        let contextual = ContextualAssessor(kind: .pushup, base: base, context: .standard)
            .assess(bottomFrames: frames, startFrames: frames)
        XCTAssertEqual(plain, contextual)
    }
}
