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
    /// The same, with the frame at the START of each repetition as well (standing, the top of a push-up, the hang of a
    /// pull-up), so the full range of the movement can be checked, not only its working end. An assessor that does
    /// not use them falls back to `assess(bottomFrames:)`.
    func assess(bottomFrames: [PoseFrame], startFrames: [PoseFrame]) -> TechniqueAssessment
}

public extension TechniqueAssessing {
    func assess(bottomFrames: [PoseFrame], startFrames: [PoseFrame]) -> TechniqueAssessment {
        assess(bottomFrames: bottomFrames)
    }
}

func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }

/// Simple squat assessment from a side view: depth and torso lean, with the knee angle reported next to the depth.
/// Depth follows the powerlifting rule (the hip down to the level of the knee); the knee angle is shown against the
/// reference band because the hip-knee test alone cannot tell a shallow squat from a camera that is tilted.
public struct BasicSquatAssessor: TechniqueAssessing {
    public var maxTorsoLean = 45.0
    /// Hip may be this far (frame fraction) above the knee and still count as "deep enough".
    public var depthTolerance = 0.02
    /// Knee angle at the lowest point of a squat that reached about parallel (reported next to the depth).
    public var kneeParallelMax = 70.0

    public init() {}

    public init(reference: AngleReference) {
        maxTorsoLean = reference.squatTorsoLeanMax
        depthTolerance = reference.squatDepthTolerance
        kneeParallelMax = reference.squatKneeParallelMax
    }

    public func assess(bottomFrames: [PoseFrame]) -> TechniqueAssessment {
        var deepEnough = 0
        var leanTooHigh = 0
        var measured = 0
        var kneeAngles: [Double] = []
        var leans: [Double] = []

        for frame in bottomFrames {
            guard let neck = frame.joint(.neck) else { continue }
            let hip = frame.joint(.root) ?? frame.joint(.leftHip) ?? frame.joint(.rightHip)
            let knee = frame.joint(.leftKnee) ?? frame.joint(.rightKnee)
            guard let hip, let knee else { continue }
            measured += 1
            if hip.y >= knee.y - depthTolerance { deepEnough += 1 }
            let lean = frame.angleFromVertical(from: hip, to: neck)
            leans.append(lean)
            if lean > maxTorsoLean { leanTooHigh += 1 }
            if let leg = PoseLimbs.leg(in: frame) { kneeAngles.append(leg.kneeAngle(in: frame)) }
        }
        guard measured > 0 else { return TechniqueAssessment(score: nil, findings: []) }

        let kneeText = kneeAngles.isEmpty ? "" : " Kąt kolana w najniższym punkcie: średnio \(degrees(average(kneeAngles)))."
        let leanText = leans.isEmpty ? "" : " Średnio \(degrees(average(leans))) od pionu (granica ok. \(degrees(maxTorsoLean)))."

        var findings: [TechniqueFinding] = []
        let shallow = measured - deepEnough
        findings.append(shallow == 0
            ? TechniqueFinding(id: "depth_ok", title: "Głębokość",
                               detail: "Biodra schodzą do poziomu kolan lub niżej we wszystkich powtórzeniach." + kneeText,
                               severity: .good, repsAffected: 0, repsTotal: measured)
            : TechniqueFinding(id: "depth_shallow", title: "Za płytko",
                               detail: "Biodra nie schodzą do poziomu kolan. Zejdź niżej, o ile pozwala na to komfort."
                                   + kneeText + (kneeAngles.isEmpty ? "" : " Przysiad do równoległej to kąt poniżej ok. \(degrees(kneeParallelMax))."),
                               severity: shallow * 2 > measured ? .major : .minor, repsAffected: shallow, repsTotal: measured))
        findings.append(leanTooHigh == 0
            ? TechniqueFinding(id: "torso_ok", title: "Tułów", detail: "Pochylenie tułowia mieści się w zakresie." + leanText,
                               severity: .good, repsAffected: 0, repsTotal: measured)
            : TechniqueFinding(id: "torso_lean_high", title: "Pochylenie tułowia",
                               detail: "Tułów pochyla się za bardzo w najniższym punkcie. Klatka do przodu, plecy proste." + leanText,
                               severity: leanTooHigh * 2 > measured ? .major : .minor, repsAffected: leanTooHigh, repsTotal: measured))

        let depthScore = 100.0 * Double(deepEnough) / Double(measured)
        let torsoScore = 100.0 * Double(measured - leanTooHigh) / Double(measured)
        return TechniqueAssessment(score: Int((0.55 * depthScore + 0.45 * torsoScore).rounded()), findings: findings)
    }
}

func average(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
