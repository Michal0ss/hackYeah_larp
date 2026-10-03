import Foundation
import Contracts

public struct TechniqueAssessment: Equatable, Sendable {
    /// 0...100, nil when nothing could be assessed.
    public var score: Int?
    public var findings: [TechniqueFinding]

    public init(score: Int?, findings: [TechniqueFinding]) {
        self.score = score
        self.findings = findings
    }
}

/// Assesses technique from the frame at the deepest point of each repetition.
/// The default implementation is `BasicSquatAssessor`. Bartek's full scorer (Analysis module) can replace it.
public protocol TechniqueAssessing: Sendable {
    func assess(bottomFrames: [PoseFrame]) -> TechniqueAssessment
}

enum Geometry {
    /// Angle at `b` between `a-b` and `c-b`, in degrees.
    static func angle(_ a: Joint, _ b: Joint, _ c: Joint) -> Double {
        let v1 = (x: a.x - b.x, y: a.y - b.y)
        let v2 = (x: c.x - b.x, y: c.y - b.y)
        let dot = v1.x * v2.x + v1.y * v2.y
        let norm = hypot(v1.x, v1.y) * hypot(v2.x, v2.y)
        guard norm > 0 else { return 180 }
        return acos(min(1, max(-1, dot / norm))) * 180 / .pi
    }

    /// Angle between the vector `from -> to` and the vertical, in degrees.
    static func angleFromVertical(from: Joint, to: Joint) -> Double {
        atan2(abs(to.x - from.x), abs(to.y - from.y)) * 180 / .pi
    }
}

/// Simple squat assessment from a side view: depth and torso lean.
/// Thresholds are engineering values for the demo, not norms from a trainer.
public struct BasicSquatAssessor: TechniqueAssessing {
    public var maxTorsoLean = 45.0
    /// Hip may be this far (frame fraction) above the knee and still count as "deep enough".
    public var depthTolerance = 0.02

    public init() {}

    public func assess(bottomFrames: [PoseFrame]) -> TechniqueAssessment {
        var deepEnough = 0
        var leanTooHigh = 0
        var measured = 0

        for frame in bottomFrames {
            guard let neck = frame.joint(.neck) else { continue }
            let hip = frame.joint(.root) ?? frame.joint(.leftHip) ?? frame.joint(.rightHip)
            let knee = frame.joint(.leftKnee) ?? frame.joint(.rightKnee)
            guard let hip, let knee else { continue }
            measured += 1
            if hip.y >= knee.y - depthTolerance { deepEnough += 1 }
            if Geometry.angleFromVertical(from: hip, to: neck) > maxTorsoLean { leanTooHigh += 1 }
        }
        guard measured > 0 else { return TechniqueAssessment(score: nil, findings: []) }

        var findings: [TechniqueFinding] = []
        let shallow = measured - deepEnough
        findings.append(shallow == 0
            ? TechniqueFinding(id: "depth_ok", title: "Głębokość", detail: "Biodra schodzą do poziomu kolan lub niżej we wszystkich powtórzeniach.",
                               severity: .good, repsAffected: 0, repsTotal: measured)
            : TechniqueFinding(id: "depth_shallow", title: "Za płytko",
                               detail: "Biodra nie schodzą do poziomu kolan. Zejdź niżej, o ile pozwala na to komfort.",
                               severity: shallow * 2 > measured ? .major : .minor, repsAffected: shallow, repsTotal: measured))
        findings.append(leanTooHigh == 0
            ? TechniqueFinding(id: "torso_ok", title: "Tułów", detail: "Pochylenie tułowia mieści się w zakresie.",
                               severity: .good, repsAffected: 0, repsTotal: measured)
            : TechniqueFinding(id: "torso_lean_high", title: "Pochylenie tułowia",
                               detail: "Tułów pochyla się za bardzo w najniższym punkcie. Klatka do przodu, plecy proste.",
                               severity: leanTooHigh * 2 > measured ? .major : .minor, repsAffected: leanTooHigh, repsTotal: measured))

        let depthScore = 100.0 * Double(deepEnough) / Double(measured)
        let torsoScore = 100.0 * Double(measured - leanTooHigh) / Double(measured)
        return TechniqueAssessment(score: Int((0.55 * depthScore + 0.45 * torsoScore).rounded()), findings: findings)
    }
}
