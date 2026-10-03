import Foundation
import Contracts

/// Turns pose frames into a single `depth` number for the squat.
/// depth = how far the hips are below the standing position, in torso lengths.
/// Calibrates itself while the person stands still at the start of the set.
public struct SquatSignal {
    public enum Stage: Equatable, Sendable {
        case calibrating(progress: Double)
        case ready
    }

    private struct Sample { var t: Double; var hipY: Double; var torso: Double }

    public private(set) var stage: Stage = .calibrating(progress: 0)
    public let kind: MovementKind
    private var samples: [Sample] = []
    private var standingY = 0.0
    private var torsoLength = 1.0

    /// Seconds of stillness needed to calibrate.
    public var calibrationSeconds = 1.0
    /// Max movement (frame fraction) allowed during calibration.
    public var stillnessTolerance = 0.012

    public init(kind: MovementKind = .squat) {
        self.kind = kind
    }

    public mutating func reset() {
        self = SquatSignal(kind: kind)
    }

    /// Height (0 = top of the frame) of the point that follows the movement, and torso length, if visible.
    /// Squat: the hips. Push-up and pull-up: the neck (shoulder line).
    /// The torso length is measured in image-height units (see `PoseGeometry`), so a portrait video does not stretch it.
    /// Public: Analysis reuses it to find repetitions in a recorded clip.
    public static func measure(_ frame: PoseFrame, kind: MovementKind = .squat,
                               minConfidence: Double = 0.3) -> (hipY: Double, torso: Double)? {
        if kind != .squat {
            guard let neck = frame.joint(.neck, minConfidence: minConfidence) ?? shoulderMid(frame, minConfidence: minConfidence),
                  let root = frame.joint(.root, minConfidence: minConfidence) ?? frame.joint(.leftHip, minConfidence: minConfidence)
                      ?? frame.joint(.rightHip, minConfidence: minConfidence) else { return nil }
            let torso = frame.distance(neck, root)
            guard torso > 0.02 else { return nil }
            return (neck.y, torso)
        }
        let hipY: Double
        if let l = frame.joint(.leftHip, minConfidence: minConfidence), let r = frame.joint(.rightHip, minConfidence: minConfidence) {
            hipY = (l.y + r.y) / 2
        } else if let root = frame.joint(.root, minConfidence: minConfidence) {
            hipY = root.y
        } else if let any = frame.joint(.leftHip, minConfidence: minConfidence) ?? frame.joint(.rightHip, minConfidence: minConfidence) {
            hipY = any.y
        } else {
            return nil
        }
        guard let neck = frame.joint(.neck, minConfidence: minConfidence),
              let root = frame.joint(.root, minConfidence: minConfidence) ?? frame.joint(.leftHip, minConfidence: minConfidence)
                  ?? frame.joint(.rightHip, minConfidence: minConfidence) else {
            return nil
        }
        let torso = frame.distance(neck, root)
        guard torso > 0.02 else { return nil }
        return (hipY, torso)
    }

    private static func shoulderMid(_ frame: PoseFrame, minConfidence: Double) -> Joint? {
        guard let l = frame.joint(.leftShoulder, minConfidence: minConfidence),
              let r = frame.joint(.rightShoulder, minConfidence: minConfidence) else {
            return frame.joint(.leftShoulder, minConfidence: minConfidence) ?? frame.joint(.rightShoulder, minConfidence: minConfidence)
        }
        return Joint(name: .neck, x: (l.x + r.x) / 2, y: (l.y + r.y) / 2, confidence: min(l.confidence, r.confidence))
    }

    /// Returns the current depth, or nil when the person is not visible enough or still calibrating.
    public mutating func depth(for frame: PoseFrame) -> Double? {
        guard let m = Self.measure(frame, kind: kind) else { return nil }
        switch stage {
        case .ready:
            // Pull-up: the body rises, so the screen height DEcreases while the movement progresses.
            return (kind == .pullup ? (standingY - m.hipY) : (m.hipY - standingY)) / torsoLength
        case .calibrating:
            samples.append(Sample(t: frame.time, hipY: m.hipY, torso: m.torso))
            samples.removeAll { frame.time - $0.t > calibrationSeconds * 1.3 }
            let span = (samples.last?.t ?? 0) - (samples.first?.t ?? 0)
            let ys = samples.map(\.hipY)
            let still = (ys.max() ?? 0) - (ys.min() ?? 0) <= stillnessTolerance
            if !still {
                // Movement: restart the window from the newest sample.
                samples = [Sample(t: frame.time, hipY: m.hipY, torso: m.torso)]
                stage = .calibrating(progress: 0)
                return nil
            }
            stage = .calibrating(progress: min(span / calibrationSeconds, 1))
            if span >= calibrationSeconds, samples.count >= 8 {
                standingY = ys.sorted()[ys.count / 2]
                torsoLength = samples.map(\.torso).sorted()[samples.count / 2]
                stage = .ready
                return 0
            }
            return nil
        }
    }
}
