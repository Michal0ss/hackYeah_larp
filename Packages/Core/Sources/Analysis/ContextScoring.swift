import Contracts
import Foundation
import LiveSet

/// Scoring a recorded clip with the person's context (`TechniqueContext`): the allowances for this exercise, with the
/// proportions measured from the clip itself. The live set does the same through `ContextualAssessor`, so a clip and a
/// set are judged by the same rules.
public enum ContextScoring {
    /// The allowances for `kind`. For a squat the thigh-to-torso proportion is measured on the start and the lowest
    /// frame of every repetition found in `frames`; for the other exercises proportions play no part.
    public static func adjustment(for context: TechniqueContext, kind: MovementKind, frames: [PoseFrame],
                                  reference: AngleReference, rules: ContextRules = ContextRules(),
                                  clip: ClipRepDetector.Config = ClipRepDetector.Config()) -> ContextAdjustment {
        var ratio: Double?
        if kind == .squat {
            let analysis = RepAnalyzer.analyze(frames: frames, kind: kind, config: clip,
                                               depthTolerance: reference.squatDepthTolerance)
            ratio = BodyProportions.thighToTorso(in: analysis.startFrames + analysis.bottomFrames)
        }
        return context.adjustment(for: kind, base: reference, rules: rules, thighToTorso: ratio)
    }
}

public extension TechniqueScorer.Thresholds {
    /// The squat scorer's own limits with the person's allowances: the torso lean limit follows the one in the angle
    /// reference, and the spread between repetitions that still counts as repeatable grows by its share.
    func adjusted(by adjustment: ContextAdjustment) -> TechniqueScorer.Thresholds {
        var copy = self
        copy.maxTorsoLeanDegrees += adjustment.torsoLeanExtra
        copy.repeatabilityToleranceDegrees += adjustment.repeatabilityExtra
        return copy
    }
}
