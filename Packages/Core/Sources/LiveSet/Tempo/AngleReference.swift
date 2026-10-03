import Foundation
import Contracts

/// Reference values for the joint angles of each exercise, in degrees. Angles are interior angles of the joint
/// (180 = a straight limb) measured on the 2D side view, with the image aspect ratio corrected (`PoseFrame.angle`).
///
/// Where each number comes from, and how sure we are about it, is written down in `docs/ANALIZA_TECHNIKI.md`. Short
/// version: depth of the squat follows the powerlifting rule (hip below the top of the knee) and the knee flexion
/// measured at the parallel position (about 124 degrees of flexion = 56 degrees interior, Cotter et al. 2013); the
/// push-up follows the usual test standard (elbows to 90 degrees, straight body line); the pull-up follows the
/// definition of a full repetition (full hang to chin over the bar). Everything is a starting value to be tuned on
/// real recordings, and a 2D pose estimate is itself off by several degrees, so these are bands, not exact limits.
///
/// Loaded from `content/config/scoring.json`, section "angles". Missing keys keep the defaults.
public struct AngleReference: Sendable, Equatable {
    // Squat
    /// Knee angle at the lowest point of a squat that reached about parallel (thigh horizontal) or deeper. Parallel
    /// is about 56 degrees (124 degrees of flexion); the limit is looser by the error of a 2D estimate.
    public var squatKneeParallelMax = 70.0
    /// Knee angle of a squat clearly below parallel (about 40 degrees, 140 degrees of flexion; same allowance).
    public var squatKneeDeepMax = 50.0
    /// Torso lean from the vertical at the lowest point above which the lean is flagged.
    public var squatTorsoLeanMax = 45.0
    /// Hip may be this far (fraction of the image height) above the knee and still count as parallel.
    public var squatDepthTolerance = 0.02

    // Push-up
    /// Elbow angle at the bottom at or below which the repetition has a full range.
    public var pushupElbowBottomMax = 100.0
    /// Elbow angle at the bottom of a clean push-up (chest about at the height of the hands).
    public var pushupElbowIdeal = 90.0
    /// Elbow angle at the top at or above which the arms count as extended.
    public var pushupElbowTopMin = 155.0
    /// Shoulder - hip - ankle angle at or above which the body counts as one straight line.
    public var pushupBodyLineMin = 160.0

    // Pull-up
    /// Elbow angle at the top at or below which the elbows count as bent.
    public var pullupElbowTopMax = 100.0
    /// Elbow angle in the hang at or above which the arms count as extended (a full range starts there).
    public var pullupElbowHangMin = 155.0
    /// How far above the wrists (fraction of the image height) the nose must be at the top.
    public var pullupNoseMargin = 0.02

    public init() {}

    public init(values: [String: Double]) {
        self.init()
        squatKneeParallelMax = values["squatKneeParallelMax"] ?? squatKneeParallelMax
        squatKneeDeepMax = values["squatKneeDeepMax"] ?? squatKneeDeepMax
        squatTorsoLeanMax = values["squatTorsoLeanMax"] ?? squatTorsoLeanMax
        squatDepthTolerance = values["squatDepthTolerance"] ?? squatDepthTolerance
        pushupElbowBottomMax = values["pushupElbowBottomMax"] ?? pushupElbowBottomMax
        pushupElbowIdeal = values["pushupElbowIdeal"] ?? pushupElbowIdeal
        pushupElbowTopMin = values["pushupElbowTopMin"] ?? pushupElbowTopMin
        pushupBodyLineMin = values["pushupBodyLineMin"] ?? pushupBodyLineMin
        pullupElbowTopMax = values["pullupElbowTopMax"] ?? pullupElbowTopMax
        pullupElbowHangMin = values["pullupElbowHangMin"] ?? pullupElbowHangMin
        pullupNoseMargin = values["pullupNoseMargin"] ?? pullupNoseMargin
    }
}

/// Which angle the chart and the live readout follow for each exercise, and the band the reference allows.
public extension MovementKind {
    /// The main angle of the exercise: the knee for a squat, the elbow for a push-up and a pull-up.
    var primaryAngleTitle: String {
        switch self {
        case .squat: return "Kąt kolana"
        case .pushup, .pullup: return "Kąt łokcia"
        }
    }

    /// The band of the primary angle at the working end of the movement (the bottom of a squat and a push-up, the
    /// top of a pull-up): lower bound, upper bound.
    func targetBand(_ reference: AngleReference) -> ClosedRange<Double> {
        switch self {
        case .squat: return (reference.squatKneeDeepMax - 10)...reference.squatKneeParallelMax
        case .pushup: return 60...reference.pushupElbowBottomMax
        case .pullup: return 40...reference.pullupElbowTopMax
        }
    }

    /// The primary angle in one frame, from the better visible side. Nil when the three joints are not visible.
    func primaryAngle(in frame: PoseFrame, minConfidence: Double = 0.2) -> Double? {
        switch self {
        case .squat: return PoseLimbs.leg(in: frame, minConfidence: minConfidence)?.kneeAngle(in: frame)
        case .pushup, .pullup: return PoseLimbs.arm(in: frame, minConfidence: minConfidence)?.elbowAngle(in: frame)
        }
    }
}

public extension MovementKind {
    /// A frame near `time` (within `radius` seconds) at the bent end (`wantMin`: the working end of a squat, a push-up
    /// and a pull-up) or at the extended end (the start position) of the exercise's joint angle.
    ///
    /// It is not the single most extreme frame but the one a quarter in from that end, so a tracking glitch of one or
    /// two frames cannot become the "deepest point". Nil when no frame there shows the joints.
    func representativeFrame(in frames: [PoseFrame], around time: Double, radius: Double, wantMin: Bool,
                             minConfidence: Double = 0.15) -> PoseFrame? {
        var candidates: [(frame: PoseFrame, angle: Double)] = []
        for frame in frames where abs(frame.time - time) <= radius {
            if let angle = primaryAngle(in: frame, minConfidence: minConfidence) { candidates.append((frame, angle)) }
        }
        guard !candidates.isEmpty else { return nil }
        candidates.sort { $0.angle < $1.angle }
        let rank = Int((0.25 * Double(candidates.count - 1)).rounded())
        return wantMin ? candidates[rank].frame : candidates[candidates.count - 1 - rank].frame
    }
}
