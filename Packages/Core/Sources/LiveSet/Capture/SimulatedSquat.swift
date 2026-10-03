import Foundation
import Contracts

/// A synthetic side-view squat, so the whole live-set flow runs on the simulator and in tests
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

    public init() {}

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
