import Foundation
import Contracts

/// The better visible leg and arm of a frame. In a side view one side is often hidden behind the other, so every
/// angle is taken from the side whose three joints Vision is most sure about (never mixing the two sides).
public enum PoseLimbs {
    public struct Leg: Sendable {
        public var hip: Joint, knee: Joint, ankle: Joint
        public var confidence: Double { min(hip.confidence, knee.confidence, ankle.confidence) }
        /// Knee angle in degrees (180 = straight leg), aspect corrected.
        public func kneeAngle(in frame: PoseFrame) -> Double { frame.angle(hip, knee, ankle) }
    }

    public struct Arm: Sendable {
        public var shoulder: Joint, elbow: Joint, wrist: Joint
        public var confidence: Double { min(shoulder.confidence, elbow.confidence, wrist.confidence) }
        /// Elbow angle in degrees (180 = straight arm), aspect corrected.
        public func elbowAngle(in frame: PoseFrame) -> Double { frame.angle(shoulder, elbow, wrist) }
    }

    public static func leg(in frame: PoseFrame, minConfidence: Double = 0.2) -> Leg? {
        func side(_ h: JointName, _ k: JointName, _ a: JointName) -> Leg? {
            guard let hip = frame.joint(h, minConfidence: minConfidence), let knee = frame.joint(k, minConfidence: minConfidence),
                  let ankle = frame.joint(a, minConfidence: minConfidence) else { return nil }
            return Leg(hip: hip, knee: knee, ankle: ankle)
        }
        return [side(.leftHip, .leftKnee, .leftAnkle), side(.rightHip, .rightKnee, .rightAnkle)]
            .compactMap { $0 }.max { $0.confidence < $1.confidence }
    }

    public static func arm(in frame: PoseFrame, minConfidence: Double = 0.2) -> Arm? {
        func side(_ s: JointName, _ e: JointName, _ w: JointName) -> Arm? {
            guard let shoulder = frame.joint(s, minConfidence: minConfidence), let elbow = frame.joint(e, minConfidence: minConfidence),
                  let wrist = frame.joint(w, minConfidence: minConfidence) else { return nil }
            return Arm(shoulder: shoulder, elbow: elbow, wrist: wrist)
        }
        return [side(.leftShoulder, .leftElbow, .leftWrist), side(.rightShoulder, .rightElbow, .rightWrist)]
            .compactMap { $0 }.max { $0.confidence < $1.confidence }
    }
}
