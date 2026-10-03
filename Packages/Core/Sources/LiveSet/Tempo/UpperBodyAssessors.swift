import Foundation
import Contracts

/// Push-up from a side view, judged at the lowest point of each repetition: elbow bend and a straight body line.
/// Thresholds are engineering values for the demo, to be tuned on real recordings.
public struct BasicPushupAssessor: TechniqueAssessing {
    /// Elbow angle (shoulder - elbow - wrist) at or below this counts as a full range.
    public var maxElbowAngle = 100.0
    /// Angle at the hip (shoulder - hip - ankle) at or above this counts as a straight body.
    public var minBodyLineAngle = 160.0

    public init() {}

    public func assess(bottomFrames: [PoseFrame]) -> TechniqueAssessment {
        var measured = 0, deepEnough = 0, sagging = 0, piked = 0
        for frame in bottomFrames {
            guard let side = Self.bestSide(frame) else { continue }
            measured += 1
            if Geometry.angle(side.shoulder, side.elbow, side.wrist) <= maxElbowAngle { deepEnough += 1 }
            if let hip = side.hip, let ankle = side.ankle {
                if Geometry.angle(side.shoulder, hip, ankle) < minBodyLineAngle {
                    // Hip below the shoulder-ankle line = sagging (screen y grows downwards).
                    let t = (hip.x - ankle.x) / (side.shoulder.x - ankle.x == 0 ? 1 : side.shoulder.x - ankle.x)
                    let lineY = ankle.y + t * (side.shoulder.y - ankle.y)
                    if hip.y > lineY { sagging += 1 } else { piked += 1 }
                }
            }
        }
        guard measured > 0 else { return TechniqueAssessment(score: nil, findings: []) }

        var findings: [TechniqueFinding] = []
        let shallow = measured - deepEnough
        findings.append(shallow == 0
            ? TechniqueFinding(id: "depth_ok", title: "Zakres ruchu", detail: "Łokcie zginają się do około 90° w każdym powtórzeniu.",
                               severity: .good, repsAffected: 0, repsTotal: measured)
            : TechniqueFinding(id: "pushup_shallow", title: "Za płytko",
                               detail: "Zejdź niżej, tak żeby łokcie zgięły się do około 90°.",
                               severity: shallow * 2 > measured ? .major : .minor, repsAffected: shallow, repsTotal: measured))
        let bad = sagging + piked
        findings.append(bad == 0
            ? TechniqueFinding(id: "body_line_ok", title: "Linia ciała", detail: "Ciało tworzy prostą linię od głowy do stóp.",
                               severity: .good, repsAffected: 0, repsTotal: measured)
            : TechniqueFinding(id: sagging >= piked ? "hips_sag" : "hips_high", title: "Linia ciała",
                               detail: sagging >= piked ? "Biodra opadają. Napnij brzuch i pośladki, ciało w jednej linii."
                                                        : "Biodra są za wysoko. Opuść je, ciało w jednej linii.",
                               severity: bad * 2 > measured ? .major : .minor, repsAffected: bad, repsTotal: measured))

        let depthScore = 100.0 * Double(deepEnough) / Double(measured)
        let lineScore = 100.0 * Double(measured - bad) / Double(measured)
        return TechniqueAssessment(score: Int((0.5 * depthScore + 0.5 * lineScore).rounded()), findings: findings)
    }

    private static func bestSide(_ frame: PoseFrame) -> (shoulder: Joint, elbow: Joint, wrist: Joint, hip: Joint?, ankle: Joint?)? {
        func side(_ s: JointName, _ e: JointName, _ w: JointName, _ h: JointName, _ a: JointName) -> (Joint, Joint, Joint, Joint?, Joint?, Double)? {
            guard let sh = frame.joint(s), let el = frame.joint(e), let wr = frame.joint(w) else { return nil }
            return (sh, el, wr, frame.joint(h), frame.joint(a), min(sh.confidence, el.confidence, wr.confidence))
        }
        let candidates = [side(.leftShoulder, .leftElbow, .leftWrist, .leftHip, .leftAnkle),
                          side(.rightShoulder, .rightElbow, .rightWrist, .rightHip, .rightAnkle)].compactMap { $0 }
        guard let best = candidates.max(by: { $0.5 < $1.5 }) else { return nil }
        return (best.0, best.1, best.2, best.3 ?? frame.joint(.root), best.4)
    }
}

/// Pull-up, judged at the highest point of each repetition. The bar is not detected, so "chin over the bar" is
/// approximated by the head being above the hands (which hold the bar) and the elbows being bent.
public struct BasicPullupAssessor: TechniqueAssessing {
    /// How far above the wrists (frame fraction) the nose must be.
    public var noseAboveWristsMargin = 0.02
    public var maxElbowAngle = 100.0

    public init() {}

    public func assess(bottomFrames: [PoseFrame]) -> TechniqueAssessment {
        var measured = 0, high = 0, bent = 0
        for frame in bottomFrames {
            guard let nose = frame.joint(.nose) else { continue }
            let wrists = [frame.joint(.leftWrist), frame.joint(.rightWrist)].compactMap { $0 }
            guard let wristY = wrists.map(\.y).min() else { continue }
            measured += 1
            if nose.y < wristY - noseAboveWristsMargin { high += 1 }
            if let angle = Self.elbowAngle(frame), angle <= maxElbowAngle { bent += 1 }
        }
        guard measured > 0 else { return TechniqueAssessment(score: nil, findings: []) }

        var findings: [TechniqueFinding] = []
        let low = measured - high
        findings.append(low == 0
            ? TechniqueFinding(id: "top_ok", title: "Górna pozycja", detail: "Głowa przechodzi nad linię rąk w każdym powtórzeniu.",
                               severity: .good, repsAffected: 0, repsTotal: measured)
            : TechniqueFinding(id: "pullup_low", title: "Za nisko",
                               detail: "Podciągnij się wyżej, tak żeby broda znalazła się nad drążkiem.",
                               severity: low * 2 > measured ? .major : .minor, repsAffected: low, repsTotal: measured))
        let straight = measured - bent
        findings.append(straight == 0
            ? TechniqueFinding(id: "elbows_ok", title: "Praca łokci", detail: "Łokcie zginają się w górnej pozycji.",
                               severity: .good, repsAffected: 0, repsTotal: measured)
            : TechniqueFinding(id: "elbows_open", title: "Łokcie",
                               detail: "W górnej pozycji łokcie są prawie wyprostowane. Pociągnij łokcie w dół do boków.",
                               severity: straight * 2 > measured ? .major : .minor, repsAffected: straight, repsTotal: measured))

        let highScore = 100.0 * Double(high) / Double(measured)
        let bentScore = 100.0 * Double(bent) / Double(measured)
        return TechniqueAssessment(score: Int((0.6 * highScore + 0.4 * bentScore).rounded()), findings: findings)
    }

    static func elbowAngle(_ frame: PoseFrame) -> Double? {
        func angle(_ s: JointName, _ e: JointName, _ w: JointName) -> (Double, Double)? {
            guard let sh = frame.joint(s), let el = frame.joint(e), let wr = frame.joint(w) else { return nil }
            return (Geometry.angle(sh, el, wr), min(sh.confidence, el.confidence, wr.confidence))
        }
        let sides = [angle(.leftShoulder, .leftElbow, .leftWrist), angle(.rightShoulder, .rightElbow, .rightWrist)].compactMap { $0 }
        return sides.max(by: { $0.1 < $1.1 })?.0
    }
}
