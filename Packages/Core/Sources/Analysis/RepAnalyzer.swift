import Contracts
import Foundation
import LiveSet

/// Splits a recorded clip into repetitions and measures the angle/tempo metrics PROJECT.md 6.3 asks for.
/// Repetitions come from `ClipRepDetector` (the whole clip at once, no live calibration), angles from the
/// aspect-corrected `PoseFrame.angle`, so squat, push-up and pull-up all measure real joint angles.
public enum RepAnalyzer {
    /// Hip may be this far (frame fraction) above the knee and still count as deep enough. Squat only.
    public static var depthToleranceFrame = 0.02

    public struct Analysis {
        public var reps: [RepMetrics]
        /// One frame per rep: the working end of the movement (deepest point of a squat/push-up, highest of a
        /// pull-up), the one a `TechniqueAssessing` judges.
        public var bottomFrames: [PoseFrame]
        /// One frame per rep: the position it started from (standing, the top of a push-up, the hang).
        public var startFrames: [PoseFrame]
        /// What the detector saw, for charts and for explaining a clip without repetitions.
        public var detection: ClipRepDetection
        public var clipReps: [ClipRep] { detection.reps }
    }

    public static func analyze(frames: [PoseFrame], kind: MovementKind = .squat,
                               config: ClipRepDetector.Config = ClipRepDetector.Config(),
                               depthTolerance: Double = RepAnalyzer.depthToleranceFrame) -> Analysis {
        let detection = ClipRepDetector.detect(frames: frames, kind: kind, config: config)
        var metrics: [RepMetrics] = []
        for rep in detection.reps {
            let window = frames.filter { $0.time >= rep.startTime && $0.time <= rep.endTime }
            // The pull-up is reversed: the way out is the pull (concentric), the way back is the lowering.
            let descent = kind == .pullup ? rep.backSeconds : rep.outSeconds
            let ascent = kind == .pullup ? rep.outSeconds : rep.backSeconds
            metrics.append(self.metrics(index: rep.index, frames: window, bottom: rep.bottomFrame,
                                        descent: descent, ascent: ascent, depthTolerance: depthTolerance))
        }
        return Analysis(reps: metrics, bottomFrames: detection.reps.map(\.bottomFrame),
                        startFrames: detection.reps.map(\.startFrame), detection: detection)
    }

    /// Per-rep metrics (knee angle, hip depth, torso lean). For push-up/pull-up only the tempo is meaningful here;
    /// their scoring comes from the `TechniqueAssessing` the live set uses.
    private static func metrics(index: Int, frames: [PoseFrame], bottom: PoseFrame, descent: Double, ascent: Double,
                                depthTolerance: Double) -> RepMetrics {
        var minAngle = 180.0
        var leanAtBottom = 0.0
        var hipBelowKnee = false

        // The angles of the frame the detector chose as the working end of the repetition (not the most extreme frame
        // of the window, which could be a tracking glitch). Only when the legs are not visible there, the window is used.
        for frame in [bottom] + frames {
            guard let leg = PoseLimbs.leg(in: frame, minConfidence: 0.15) else { continue }
            minAngle = leg.kneeAngle(in: frame)
            hipBelowKnee = leg.hip.y >= leg.knee.y - depthTolerance
            if let neck = frame.joint(.neck, minConfidence: 0.15) {
                leanAtBottom = frame.angleFromVertical(from: leg.hip, to: neck)
            }
            break
        }

        return RepMetrics(index: index, minKneeAngle: minAngle, hipBelowKnee: hipBelowKnee,
                          torsoLeanDegrees: leanAtBottom, descentSeconds: descent, ascentSeconds: ascent)
    }

    /// The main angle of the exercise (knee for a squat, elbow for a push-up and a pull-up) at every frame where its
    /// three joints are visible, for charting over time. Smoothed the same way `ClipRepDetector` smooths its depth
    /// signal (a median of nearby samples, then a short moving average), so one bad Vision frame doesn't spike the
    /// chart — scoring already picks a robust single frame per repetition (`MovementKind.representativeFrame`); this
    /// is the same idea applied to every frame, for the line between repetitions.
    public static func angleSeries(in frames: [PoseFrame], kind: MovementKind) -> [(time: Double, angle: Double)] {
        let raw = frames.compactMap { frame -> (time: Double, angle: Double)? in
            kind.primaryAngle(in: frame, minConfidence: 0.15).map { (frame.time, $0) }
        }
        guard raw.count > 4 else { return raw }
        let times = raw.map(\.time)
        var angles = ClipRepDetector.medianFilter(raw.map(\.angle), radius: 2)
        angles = ClipRepDetector.movingAverage(angles, times: times, window: 0.2)
        return zip(times, angles).map { (time: $0, angle: $1) }
    }

    /// Knee angle at every frame where hip/knee/ankle are all visible, for charting over time (squat).
    public static func kneeAngleSeries(in frames: [PoseFrame]) -> [(time: Double, angle: Double)] {
        angleSeries(in: frames, kind: .squat)
    }

    /// The frame across the whole clip with the smallest knee angle: a representative "bottom of a squat" shot.
    public static func deepestFrame(in frames: [PoseFrame]) -> PoseFrame? {
        frames.compactMap { frame in MovementKind.squat.primaryAngle(in: frame, minConfidence: 0.15).map { (frame, $0) } }
            .min { $0.1 < $1.1 }?.0
    }
}
