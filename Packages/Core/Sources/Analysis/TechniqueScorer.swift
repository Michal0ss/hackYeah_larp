import Contracts
import Foundation
import LiveSet

/// Scores a recorded clip 0-100. Squat uses its own weighted scorer (depth/torso/repeatability/
/// tempo, PROJECT.md 6.4). Push-up and pull-up reuse `MovementKind.defaultAssessor` — the exact
/// `TechniqueAssessing` the live set scores with — so a file analysis and a live set never show two
/// different scores for the same exercise.
public enum TechniqueScorer {
    public struct Weights {
        public var depth: Double
        public var torso: Double
        public var repeatability: Double
        public var tempo: Double

        public init(depth: Double = 0.35, torso: Double = 0.3, repeatability: Double = 0.2, tempo: Double = 0.15) {
            self.depth = depth
            self.torso = torso
            self.repeatability = repeatability
            self.tempo = tempo
        }

        /// Values from `content/config/scoring.json`'s "weights" section.
        public static func from(_ numbers: [String: Double]) -> Weights {
            let d = Weights()
            return Weights(depth: numbers["depth"] ?? d.depth, torso: numbers["torso"] ?? d.torso,
                          repeatability: numbers["repeatability"] ?? d.repeatability,
                          tempo: numbers["tempo"] ?? d.tempo)
        }
    }

    public struct Thresholds {
        public var maxTorsoLeanDegrees: Double
        /// Spread (degrees) of `minKneeAngle` across reps above which repeatability scores 0.
        public var repeatabilityToleranceDegrees: Double
        /// Descent at or above this is "controlled"; faster scores proportionally lower.
        public var minControlledDescentSeconds: Double

        public init(maxTorsoLeanDegrees: Double = 45, repeatabilityToleranceDegrees: Double = 15,
                    minControlledDescentSeconds: Double = 1.0) {
            self.maxTorsoLeanDegrees = maxTorsoLeanDegrees
            self.repeatabilityToleranceDegrees = repeatabilityToleranceDegrees
            self.minControlledDescentSeconds = minControlledDescentSeconds
        }

        /// Values from `content/config/scoring.json`'s "thresholds" section.
        public static func from(_ numbers: [String: Double]) -> Thresholds {
            let d = Thresholds()
            return Thresholds(
                maxTorsoLeanDegrees: numbers["maxTorsoLeanDegrees"] ?? d.maxTorsoLeanDegrees,
                repeatabilityToleranceDegrees: numbers["repeatabilityToleranceDegrees"] ?? d.repeatabilityToleranceDegrees,
                minControlledDescentSeconds: numbers["minControlledDescentSeconds"] ?? d.minControlledDescentSeconds)
        }
    }

    /// Exercise to suggest when a component score is too low (PROJECT.md 6.6). Manually curated,
    /// IDs from content/catalog.json.
    private static let lowDepthSubstitute = "box_squat"
    private static let lowTorsoSubstitute = "goblet_squat"
    private static let substituteThreshold = 60.0

    /// Entry point for the analysis screens: picks the squat scorer or the shared live-set assessor
    /// depending on `kind`.
    public static func score(exerciseId: String, kind: MovementKind, frames: [PoseFrame],
                             weights: Weights = Weights(), thresholds: Thresholds = Thresholds(),
                             reference: AngleReference = AngleReference(),
                             clip: ClipRepDetector.Config = ClipRepDetector.Config(),
                             date: Date = Date(), isSimulated: Bool = false) -> TechniqueResult {
        let analysis = RepAnalyzer.analyze(frames: frames, kind: kind, config: clip, depthTolerance: reference.squatDepthTolerance)
        guard kind == .squat else {
            let assessment = kind.assessor(reference: reference)
                .assess(bottomFrames: analysis.bottomFrames, startFrames: analysis.startFrames)
            return TechniqueResult(exerciseId: exerciseId, date: date, score: assessment.score ?? 0,
                                   componentScores: [:], findings: assessment.findings, reps: analysis.reps,
                                   isSimulated: isSimulated)
        }
        return score(exerciseId: exerciseId, reps: analysis.reps, weights: weights, thresholds: thresholds,
                    date: date, isSimulated: isSimulated)
    }

    /// Squat-only: weighted score from depth/torso/repeatability/tempo (PROJECT.md 6.4).
    public static func score(exerciseId: String, reps: [RepMetrics], weights: Weights = Weights(),
                             thresholds: Thresholds = Thresholds(), date: Date = Date(),
                             isSimulated: Bool = false) -> TechniqueResult {
        guard !reps.isEmpty else {
            return TechniqueResult(exerciseId: exerciseId, date: date, score: 0, componentScores: [:],
                                   findings: [], reps: [], isSimulated: isSimulated)
        }

        let deepReps = reps.filter(\.hipBelowKnee).count
        let depthScore = 100.0 * Double(deepReps) / Double(reps.count)

        let goodLeanReps = reps.filter { $0.torsoLeanDegrees <= thresholds.maxTorsoLeanDegrees }.count
        let torsoScore = 100.0 * Double(goodLeanReps) / Double(reps.count)

        let repeatabilityScore = repeatability(of: reps.map(\.minKneeAngle), tolerance: thresholds.repeatabilityToleranceDegrees)
        let tempoScore = tempoControl(of: reps.map(\.descentSeconds), minControlled: thresholds.minControlledDescentSeconds)

        let componentScores: [String: Int] = [
            "depth": Int(depthScore.rounded()),
            "torso": Int(torsoScore.rounded()),
            "repeatability": Int(repeatabilityScore.rounded()),
            "tempo": Int(tempoScore.rounded()),
        ]

        let overall = weights.depth * depthScore + weights.torso * torsoScore
            + weights.repeatability * repeatabilityScore + weights.tempo * tempoScore

        let kneeAverage = reps.map(\.minKneeAngle).reduce(0, +) / Double(reps.count)
        let leanAverage = reps.map(\.torsoLeanDegrees).reduce(0, +) / Double(reps.count)
        let findings = depthFindings(deepReps: deepReps, total: reps.count, kneeAverage: kneeAverage)
            + torsoFindings(goodReps: goodLeanReps, total: reps.count, leanAverage: leanAverage,
                            maxLean: thresholds.maxTorsoLeanDegrees)

        let substitute = substituteExercise(depthScore: depthScore, torsoScore: torsoScore)

        return TechniqueResult(exerciseId: exerciseId, date: date, score: Int(overall.rounded()),
                               componentScores: componentScores, findings: findings, reps: reps,
                               substituteExerciseId: substitute, isSimulated: isSimulated)
    }

    private static func repeatability(of angles: [Double], tolerance: Double) -> Double {
        guard angles.count > 1 else { return 100 }
        let mean = angles.reduce(0, +) / Double(angles.count)
        let variance = angles.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(angles.count)
        let spread = variance.squareRoot()
        return 100.0 * max(0, 1 - spread / tolerance)
    }

    private static func tempoControl(of descents: [Double], minControlled: Double) -> Double {
        guard !descents.isEmpty else { return 100 }
        let perRep = descents.map { min(1, max(0, $0 / minControlled)) }
        return 100.0 * perRep.reduce(0, +) / Double(perRep.count)
    }

    private static func depthFindings(deepReps: Int, total: Int, kneeAverage: Double) -> [TechniqueFinding] {
        let shallow = total - deepReps
        let measured = " Kąt kolana w najniższym punkcie: średnio \(Int(kneeAverage.rounded()))°."
        if shallow == 0 {
            return [TechniqueFinding(id: "depth_ok", title: "Głębokość",
                detail: "Biodra schodzą do poziomu kolan lub niżej we wszystkich powtórzeniach." + measured,
                severity: .good, repsAffected: 0, repsTotal: total)]
        }
        return [TechniqueFinding(id: "depth_shallow", title: "Za płytko",
            detail: "Biodra nie schodzą do poziomu kolan. Zejdź niżej, o ile pozwala na to komfort." + measured,
            severity: shallow * 2 > total ? .major : .minor, repsAffected: shallow, repsTotal: total)]
    }

    private static func torsoFindings(goodReps: Int, total: Int, leanAverage: Double, maxLean: Double) -> [TechniqueFinding] {
        let high = total - goodReps
        let measured = " Średnio \(Int(leanAverage.rounded()))° od pionu (granica ok. \(Int(maxLean.rounded()))°)."
        if high == 0 {
            return [TechniqueFinding(id: "torso_ok", title: "Tułów",
                detail: "Pochylenie tułowia mieści się w zakresie." + measured,
                severity: .good, repsAffected: 0, repsTotal: total)]
        }
        return [TechniqueFinding(id: "torso_lean_high", title: "Pochylenie tułowia",
            detail: "Tułów pochyla się za bardzo w najniższym punkcie. Klatka do przodu, plecy proste." + measured,
            severity: high * 2 > total ? .major : .minor, repsAffected: high, repsTotal: total)]
    }

    private static func substituteExercise(depthScore: Double, torsoScore: Double) -> String? {
        // Whichever component is worse (and below the threshold) drives the suggestion.
        guard depthScore < substituteThreshold || torsoScore < substituteThreshold else { return nil }
        return depthScore <= torsoScore ? lowDepthSubstitute : lowTorsoSubstitute
    }
}
