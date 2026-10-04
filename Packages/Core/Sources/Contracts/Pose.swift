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
    /// How many people Vision found in this frame (the rest of the frame's data is for the best-scoring one).
    public var peopleDetected: Int
    /// Width / height of the upright image the joints refer to (0.5625 for a portrait 720x1280 video). Vision
    /// normalizes x by the width and y by the height, so without this ratio angles and lengths come out distorted.
    /// Nil (older fixtures, synthetic frames) means "square": no correction.
    public var aspect: Double?

    public init(time: Double, joints: [Joint], peopleDetected: Int = 1, aspect: Double? = nil) {
        self.time = time
        self.joints = joints
        self.peopleDetected = peopleDetected
        self.aspect = aspect
    }

    private enum CodingKeys: String, CodingKey { case time, joints, peopleDetected, aspect }

    /// Custom so `peopleDetected` defaults to 1 for any `PoseFrame` JSON saved before this field
    /// existed (fixtures, caches) instead of failing to decode.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decode(Double.self, forKey: .time)
        joints = try container.decode([Joint].self, forKey: .joints)
        peopleDetected = try container.decodeIfPresent(Int.self, forKey: .peopleDetected) ?? 1
        aspect = try container.decodeIfPresent(Double.self, forKey: .aspect)
    }

    /// The joint if it was detected with at least `minConfidence`.
    public func joint(_ name: JointName, minConfidence: Double = 0.3) -> Joint? {
        // A plain loop: this is called dozens of times per frame, at 30 frames per second.
        for joint in joints where joint.name == name && joint.confidence >= minConfidence { return joint }
        return nil
    }
}
