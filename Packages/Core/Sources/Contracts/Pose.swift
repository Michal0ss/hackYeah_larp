import Foundation

/// Joints we get from Apple Vision body pose (2D, 19 joints; we use the ones below).
public enum JointName: String, Codable, CaseIterable, Sendable {
    case nose, neck
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case root
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
}

public struct Joint: Codable, Equatable, Sendable {
    public var name: JointName
    /// Normalized image coordinates, 0...1, origin top-left.
    public var x: Double
    public var y: Double
    /// Vision confidence, 0...1.
    public var confidence: Double

    public init(name: JointName, x: Double, y: Double, confidence: Double) {
        self.name = name
        self.x = x
        self.y = y
        self.confidence = confidence
    }
}

/// One video frame after pose detection. Saved as JSON fixtures for tests, so nobody needs the video.
public struct PoseFrame: Codable, Equatable, Sendable {
    /// Seconds from the start of the video.
    public var time: Double
    public var joints: [Joint]

    public init(time: Double, joints: [Joint]) {
        self.time = time
        self.joints = joints
    }

    /// The joint if it was detected with at least `minConfidence`.
    public func joint(_ name: JointName, minConfidence: Double = 0.3) -> Joint? {
        joints.first { $0.name == name && $0.confidence >= minConfidence }
    }
}
