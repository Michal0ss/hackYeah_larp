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
    private var samples: [Sample] = []
    private var standingY = 0.0
    private var torsoLength = 1.0

    /// Seconds of stillness needed to calibrate.
    public var calibrationSeconds = 1.0
    /// Max movement (frame fraction) allowed during calibration.
    public var stillnessTolerance = 0.012

    public init() {}

    public mutating func reset() {
        self = SquatSignal()
    }

    /// Hip height (0 = top of the frame) and torso length from one frame, if visible.
    static func measure(_ frame: PoseFrame) -> (hipY: Double, torso: Double)? {
        let hipY: Double
        if let l = frame.joint(.leftHip), let r = frame.joint(.rightHip) {
            hipY = (l.y + r.y) / 2
        } else if let root = frame.joint(.root) {
            hipY = root.y
        } else if let any = frame.joint(.leftHip) ?? frame.joint(.rightHip) {
            hipY = any.y
        } else {
            return nil
        }
        guard let neck = frame.joint(.neck), let root = frame.joint(.root) ?? frame.joint(.leftHip) ?? frame.joint(.rightHip) else {
            return nil
        }
        let torso = hypot(neck.x - root.x, neck.y - root.y)
        guard torso > 0.02 else { return nil }
        return (hipY, torso)
    }

    /// Returns the current depth, or nil when the person is not visible enough or still calibrating.
    public mutating func depth(for frame: PoseFrame) -> Double? {
        guard let m = Self.measure(frame) else { return nil }
        switch stage {
        case .ready:
            return (m.hipY - standingY) / torsoLength
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
