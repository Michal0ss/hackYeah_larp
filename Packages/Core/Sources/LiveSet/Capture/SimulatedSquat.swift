import Foundation
import Contracts

/// A synthetic side-view squat (or push-up, or pull-up: set `kind`), so the whole live-set flow runs on the simulator and in tests
/// without a camera. Joint coordinates follow the same convention as Vision output.
public struct SimulatedSquat: Sendable {
    /// Seconds per phase of the simulated person (deliberately a bit off the target tempo).
    public var eccentric = 2.6
    public var bottomPause = 0.8
    public var concentric = 1.6
    public var restBetweenReps = 1.4
    public var reps = 5
    /// Per-rep multiplier of the eccentric time (to demo the "wolniej w dół" correction).
    public var eccentricFactors: [Double] = [1.0, 0.95, 0.5, 0.45, 0.9]
    /// 1.0 = hip level with the knee. Smaller = shallower.
    public var depthFactors: [Double] = [1.0, 1.0, 1.0, 0.95, 1.0]
    /// Seconds standing still before the first repetition (calibration).
    public var leadIn = 2.5
    public var leadOut = 3.0
    public var fps = 30.0
    public var kind: MovementKind = .squat

    public init(kind: MovementKind = .squat) {
        self.kind = kind
    }

    private func eccentricDuration(_ rep: Int) -> Double {
        eccentric * (rep < eccentricFactors.count ? eccentricFactors[rep] : 1)
    }

    private func repDuration(_ rep: Int) -> Double {
        eccentricDuration(rep) + bottomPause + concentric
    }

    public var duration: Double {
        let work = (0..<reps).map(repDuration).reduce(0, +)
        return leadIn + work + Double(max(0, reps - 1)) * restBetweenReps + leadOut
    }

    private func smoothstep(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    /// Squat depth progress, 0 (standing) ... 1 (bottom).
    func progress(at t: Double) -> Double {
        var start = leadIn
        for rep in 0..<reps {
            let ecc = eccentricDuration(rep)
            let end = start + repDuration(rep)
            let peak = rep < depthFactors.count ? depthFactors[rep] : 1
            if t >= start && t < end {
                let local = t - start
                if local < ecc { return peak * smoothstep(local / ecc) }
                if local < ecc + bottomPause { return peak }
                return peak * (1 - smoothstep((local - ecc - bottomPause) / concentric))
            }
            start = end + restBetweenReps
        }
        return 0
    }

    public func frame(at t: Double) -> PoseFrame {
        let p = progress(at: t)
        switch kind {
        case .squat: return squatFrame(at: t, progress: p)
        case .pushup: return pushupFrame(at: t, progress: p)
        case .pullup: return pullupFrame(at: t, progress: p)
        }
    }

    private func make(_ t: Double, _ points: [(JointName, Double, Double)]) -> PoseFrame {
        func jitter(_ k: Double) -> Double { 0.0015 * sin(t * 37 + k * 5.3) }
        return PoseFrame(time: t, joints: points.enumerated().map { i, point in
            Joint(name: point.0, x: point.1 + jitter(Double(i)), y: point.2 + jitter(Double(i) + 1), confidence: 0.9)
        })
    }

    /// Side view, facing right, hands on the floor. p = 0 arms straight, p = 1 chest near the floor.
    private func pushupFrame(at t: Double, progress p: Double) -> PoseFrame {
        let ankle = (x: 0.14, y: 0.69)
        let wrist = (x: 0.69, y: 0.69)
        let neck = (x: 0.66, y: 0.50 + 0.14 * p)
        let hip = (x: ankle.x + 0.42 * (neck.x - ankle.x), y: ankle.y + 0.42 * (neck.y - ankle.y))
        let knee = (x: ankle.x + 0.22 * (neck.x - ankle.x), y: ankle.y + 0.22 * (neck.y - ankle.y))
        let mid = (x: (neck.x + wrist.x) / 2, y: (neck.y + wrist.y) / 2)
        let elbow = (x: mid.x - 0.09 * p, y: mid.y)
        return make(t, [
            (.nose, neck.x + 0.05, neck.y + 0.01), (.neck, neck.x, neck.y),
            (.leftShoulder, neck.x + 0.006, neck.y + 0.01), (.rightShoulder, neck.x - 0.006, neck.y + 0.01),
            (.leftElbow, elbow.x, elbow.y), (.rightElbow, elbow.x - 0.004, elbow.y),
            (.leftWrist, wrist.x, wrist.y), (.rightWrist, wrist.x - 0.004, wrist.y),
            (.root, hip.x, hip.y), (.leftHip, hip.x + 0.006, hip.y), (.rightHip, hip.x - 0.006, hip.y),
            (.leftKnee, knee.x + 0.004, knee.y), (.rightKnee, knee.x - 0.004, knee.y),
            (.leftAnkle, ankle.x + 0.006, ankle.y), (.rightAnkle, ankle.x - 0.006, ankle.y),
        ])
    }

    /// Front view, hanging from a bar. p = 0 dead hang, p = 1 chin over the bar. The body rises with p.
    private func pullupFrame(at t: Double, progress p: Double) -> PoseFrame {
        let rise = 0.16 * p
        let barY = 0.13
        let neck = (x: 0.50, y: 0.30 - rise)
        let hipY = 0.56 - rise
        let elbowOut = 0.09 * p
        return make(t, [
            (.nose, 0.50, neck.y - 0.06), (.neck, neck.x, neck.y),
            (.leftShoulder, 0.43, neck.y + 0.01), (.rightShoulder, 0.57, neck.y + 0.01),
            (.leftElbow, 0.40 - elbowOut, neck.y + 0.07 + (1 - p) * 0.02), (.rightElbow, 0.60 + elbowOut, neck.y + 0.07 + (1 - p) * 0.02),
            (.leftWrist, 0.38, barY), (.rightWrist, 0.62, barY),
            (.root, 0.50, hipY), (.leftHip, 0.46, hipY), (.rightHip, 0.54, hipY),
            (.leftKnee, 0.47, hipY + 0.16), (.rightKnee, 0.53, hipY + 0.16),
            (.leftAnkle, 0.47, hipY + 0.32), (.rightAnkle, 0.53, hipY + 0.32),
        ])
    }

    private func squatFrame(at t: Double, progress p: Double) -> PoseFrame {
        func jitter(_ k: Double) -> Double { 0.0015 * sin(t * 37 + k * 5.3) }

        let hip = (x: 0.50 - 0.10 * p, y: 0.52 + 0.18 * p)
        let knee = (x: 0.50 + 0.08 * p, y: 0.70)
        let lean = 0.12 + 0.55 * p
        let neck = (x: hip.x + sin(lean) * 0.22, y: hip.y - cos(lean) * 0.22)
        let nose = (x: neck.x + 0.03, y: neck.y - 0.07)

        func j(_ name: JointName, _ x: Double, _ y: Double, _ k: Double) -> Joint {
            Joint(name: name, x: x + jitter(k), y: y + jitter(k + 1), confidence: 0.9)
        }
        let joints: [Joint] = [
            j(.nose, nose.x, nose.y, 1),
            j(.neck, neck.x, neck.y, 2),
            j(.leftShoulder, neck.x + 0.012, neck.y + 0.01, 3),
            j(.rightShoulder, neck.x - 0.012, neck.y + 0.01, 4),
            j(.leftElbow, neck.x + 0.06, neck.y + 0.11, 5),
            j(.rightElbow, neck.x + 0.05, neck.y + 0.11, 6),
            j(.leftWrist, neck.x + 0.09, neck.y + 0.2, 7),
            j(.rightWrist, neck.x + 0.08, neck.y + 0.2, 8),
            j(.root, hip.x, hip.y, 9),
            j(.leftHip, hip.x + 0.006, hip.y, 10),
            j(.rightHip, hip.x - 0.006, hip.y, 11),
            j(.leftKnee, knee.x + 0.006, knee.y, 12),
            j(.rightKnee, knee.x - 0.006, knee.y, 13),
            j(.leftAnkle, 0.52, 0.88, 14),
            j(.rightAnkle, 0.48, 0.88, 15),
        ]
        return PoseFrame(time: t, joints: joints)
    }

    public func frames() -> [PoseFrame] {
        let step = 1.0 / fps
        return stride(from: 0.0, to: duration, by: step).map { frame(at: $0) }
    }

    /// Frames delivered in real time (as a camera would).
    public func stream() -> AsyncStream<PoseFrame> {
        let simulation = self
        return AsyncStream { continuation in
            let task = Task {
                let start = ContinuousClock.now
                let step = 1.0 / simulation.fps
                var t = 0.0
                while t < simulation.duration, !Task.isCancelled {
                    continuation.yield(simulation.frame(at: t))
                    t += step
                    try? await Task.sleep(until: start.advanced(by: .seconds(t)), clock: .continuous)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
