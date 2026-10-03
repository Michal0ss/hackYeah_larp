import Foundation
import Contracts

/// Numbers read straight from one pose frame, for checking on a real phone whether the skeleton makes sense:
/// which joints are seen, how sure Vision is, and the angles the technique rules use. Pure and cheap.
public struct PoseDiagnostics: Equatable, Sendable {
    public static let allJoints: [JointName] = [
        .nose, .neck, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist,
        .root, .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle,
    ]

    public var jointCount: Int
    public var meanConfidence: Double
    /// Raw names of joints Vision did not return (or returned below the confidence floor).
    public var missing: [String]
    /// Which leg the angles come from: the one whose hip, knee and ankle are all seen with the best confidence.
    public var side: String?
    /// Hip - knee - ankle angle in degrees (180 = straight leg, about 90 or less = deep squat).
    public var kneeAngle: Double?
    /// Neck-to-hip line against the vertical, in degrees (0 = upright).
    public var torsoLean: Double?
    /// Same test as `BasicSquatAssessor`: hip at or below knee height.
    public var hipBelowKnee: Bool?
    /// Shoulder - elbow - wrist angle of the clearest arm (180 = straight arm, below about 100 = bent for a push-up
    /// or the top of a pull-up).
    public var elbowAngle: Double?
    /// Shoulder - hip - ankle angle (180 = straight body line; push-up checks).
    public var bodyLineAngle: Double?
    /// Nose above the hands (pull-up: head over the bar).
    public var noseAboveWrists: Bool?
    /// Nose to lowest ankle, as a fraction of the frame height (framing checks want 0.45 ... 0.95).
    public var bodyHeight: Double?
    /// Shoulder separation / torso length; small = side view, above 0.5 = facing the camera.
    public var shoulderRatio: Double?

    public static func measure(_ frame: PoseFrame?, minConfidence: Double = 0.2) -> PoseDiagnostics {
        guard let frame else {
            return PoseDiagnostics(jointCount: 0, meanConfidence: 0, missing: allJoints.map(\.rawValue))
        }
        let seen = allJoints.compactMap { frame.joint($0, minConfidence: minConfidence) }
        let missing = allJoints.filter { frame.joint($0, minConfidence: minConfidence) == nil }.map(\.rawValue)
        var result = PoseDiagnostics(
            jointCount: seen.count,
            meanConfidence: seen.isEmpty ? 0 : seen.map(\.confidence).reduce(0, +) / Double(seen.count),
            missing: missing)

        // Best leg.
        func leg(_ hip: JointName, _ knee: JointName, _ ankle: JointName, _ label: String)
            -> (label: String, h: Joint, k: Joint, a: Joint, quality: Double)? {
            guard let h = frame.joint(hip, minConfidence: minConfidence), let k = frame.joint(knee, minConfidence: minConfidence),
                  let a = frame.joint(ankle, minConfidence: minConfidence) else { return nil }
            return (label, h, k, a, min(h.confidence, k.confidence, a.confidence))
        }
        let legs = [leg(.leftHip, .leftKnee, .leftAnkle, "lewa"), leg(.rightHip, .rightKnee, .rightAnkle, "prawa")]
            .compactMap { $0 }
        if let best = legs.max(by: { $0.quality < $1.quality }) {
            result.side = best.label
            result.kneeAngle = frame.angle(best.h, best.k, best.a)
            result.hipBelowKnee = best.h.y >= best.k.y - BasicSquatAssessor().depthTolerance
        }

        func arm(_ s: JointName, _ e: JointName, _ w: JointName) -> (Double, Double)? {
            guard let sh = frame.joint(s, minConfidence: minConfidence), let el = frame.joint(e, minConfidence: minConfidence),
                  let wr = frame.joint(w, minConfidence: minConfidence) else { return nil }
            return (frame.angle(sh, el, wr), min(sh.confidence, el.confidence, wr.confidence))
        }
        let arms = [arm(.leftShoulder, .leftElbow, .leftWrist), arm(.rightShoulder, .rightElbow, .rightWrist)].compactMap { $0 }
        result.elbowAngle = arms.max(by: { $0.1 < $1.1 })?.0
        if let nose = frame.joint(.nose, minConfidence: minConfidence),
           let wristY = [frame.joint(.leftWrist, minConfidence: minConfidence), frame.joint(.rightWrist, minConfidence: minConfidence)]
            .compactMap({ $0?.y }).min() {
            result.noseAboveWrists = nose.y < wristY - 0.02
        }

        let hip = frame.joint(.root, minConfidence: minConfidence) ?? frame.joint(.leftHip, minConfidence: minConfidence)
            ?? frame.joint(.rightHip, minConfidence: minConfidence)
        if let hip, let shoulder = frame.joint(.neck, minConfidence: minConfidence),
           let ankle = frame.joint(.leftAnkle, minConfidence: minConfidence) ?? frame.joint(.rightAnkle, minConfidence: minConfidence) {
            result.bodyLineAngle = frame.angle(shoulder, hip, ankle)
        }
        if let neck = frame.joint(.neck, minConfidence: minConfidence), let hip {
            result.torsoLean = frame.angleFromVertical(from: hip, to: neck)
            if let l = frame.joint(.leftShoulder, minConfidence: minConfidence),
               let r = frame.joint(.rightShoulder, minConfidence: minConfidence) {
                let torso = frame.distance(neck, hip)
                if torso > 0.02 { result.shoulderRatio = abs(l.x - r.x) * frame.aspectRatio / torso }
            }
        }
        if let nose = frame.joint(.nose, minConfidence: minConfidence),
           let lowest = [frame.joint(.leftAnkle, minConfidence: minConfidence), frame.joint(.rightAnkle, minConfidence: minConfidence)]
            .compactMap({ $0?.y }).max() {
            result.bodyHeight = lowest - nose.y
        }
        return result
    }
}
