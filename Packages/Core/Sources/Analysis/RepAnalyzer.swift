import Contracts
import Foundation
import LiveSet

/// Splits a recorded squat clip into repetitions and measures the angle/tempo metrics
/// PROJECT.md 6.3 asks for. Reuses `SquatSignal`/`PhaseTracker` (the same rep-splitting LiveSet
/// does live) instead of re-deriving the hip-depth signal from scratch.
public enum RepAnalyzer {
    /// Hip may be this far (frame fraction) above the knee and still count as deep enough.
    public static var depthToleranceFrame = 0.02

    public static func analyze(frames: [PoseFrame]) -> [RepMetrics] {
        var signal = SquatSignal()
        var tracker = PhaseTracker()
        var results: [RepMetrics] = []
        var currentRepFrames: [PoseFrame] = []
        var collecting = false

        for frame in frames {
            guard let depth = signal.depth(for: frame) else { continue }
            let events = tracker.update(time: frame.time, depth: depth)

            if events.contains(where: { if case .phaseStarted(.eccentric, _) = $0 { return true }; return false }) {
                collecting = true
                currentRepFrames = []
            }
            if collecting { currentRepFrames.append(frame) }

            for event in events {
                if case let .repCompleted(tempo) = event {
                    results.append(metrics(for: tempo, frames: currentRepFrames))
                    collecting = false
                    currentRepFrames = []
                }
            }
        }
        return results
    }

    private static func metrics(for tempo: RepTempo, frames: [PoseFrame]) -> RepMetrics {
        var minAngle = 180.0
        var leanAtBottom = 0.0
        var hipBelowKnee = false

        for frame in frames {
            guard let hip = frame.joint(.root) ?? frame.joint(.leftHip) ?? frame.joint(.rightHip),
                  let knee = frame.joint(.leftKnee) ?? frame.joint(.rightKnee),
                  let ankle = frame.joint(.leftAnkle) ?? frame.joint(.rightAnkle)
            else { continue }

            let angle = kneeAngle(hip: hip, knee: knee, ankle: ankle)
            guard angle < minAngle else { continue }
            minAngle = angle
            hipBelowKnee = hip.y >= knee.y - depthToleranceFrame
            if let neck = frame.joint(.neck) {
                leanAtBottom = angleFromVertical(from: hip, to: neck)
            }
        }

        return RepMetrics(index: tempo.index, minKneeAngle: minAngle, hipBelowKnee: hipBelowKnee,
                          torsoLeanDegrees: leanAtBottom, descentSeconds: tempo.eccentric,
                          ascentSeconds: tempo.concentric)
    }

    /// Knee angle at every frame where hip/knee/ankle are all visible — for charting over time.
    public static func kneeAngleSeries(in frames: [PoseFrame]) -> [(time: Double, angle: Double)] {
        frames.compactMap { frame in
            guard let hip = frame.joint(.root) ?? frame.joint(.leftHip) ?? frame.joint(.rightHip),
                  let knee = frame.joint(.leftKnee) ?? frame.joint(.rightKnee),
                  let ankle = frame.joint(.leftAnkle) ?? frame.joint(.rightAnkle)
            else { return nil }
            return (frame.time, kneeAngle(hip: hip, knee: knee, ankle: ankle))
        }
    }

    /// The frame across the whole clip with the smallest knee angle — a representative "bottom of a
    /// squat" shot to overlay the skeleton on.
    public static func deepestFrame(in frames: [PoseFrame]) -> PoseFrame? {
        frames.min { angleOrInfinity($0) < angleOrInfinity($1) }
    }

    private static func angleOrInfinity(_ frame: PoseFrame) -> Double {
        guard let hip = frame.joint(.root) ?? frame.joint(.leftHip) ?? frame.joint(.rightHip),
              let knee = frame.joint(.leftKnee) ?? frame.joint(.rightKnee),
              let ankle = frame.joint(.leftAnkle) ?? frame.joint(.rightAnkle)
        else { return .infinity }
        return kneeAngle(hip: hip, knee: knee, ankle: ankle)
    }

    /// Angle at the knee between the hip and the ankle, in degrees (180 = straight leg).
    private static func kneeAngle(hip: Joint, knee: Joint, ankle: Joint) -> Double {
        let v1 = (x: hip.x - knee.x, y: hip.y - knee.y)
        let v2 = (x: ankle.x - knee.x, y: ankle.y - knee.y)
        let dot = v1.x * v2.x + v1.y * v2.y
        let norm = hypot(v1.x, v1.y) * hypot(v2.x, v2.y)
        guard norm > 0 else { return 180 }
        return acos(min(1, max(-1, dot / norm))) * 180 / .pi
    }

    /// Angle between the vector `from -> to` and the vertical, in degrees.
    private static func angleFromVertical(from: Joint, to: Joint) -> Double {
        atan2(abs(to.x - from.x), abs(to.y - from.y)) * 180 / .pi
    }
}
