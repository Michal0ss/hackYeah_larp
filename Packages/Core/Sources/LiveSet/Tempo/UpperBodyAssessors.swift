import Foundation
import Contracts

/// Push-up from a side view, judged at the lowest point of each repetition: elbow bend and a straight body line.
/// With the start frames (the top of each repetition) it also checks that the arms were extended.
/// Thresholds come from `AngleReference` (sources in docs/ANALIZA_TECHNIKI.md) and are to be tuned on real recordings.
public struct BasicPushupAssessor: TechniqueAssessing {
    /// Elbow angle (shoulder - elbow - wrist) at or below this counts as a full range.
    public var maxElbowAngle = 100.0
    /// Angle at the hip (shoulder - hip - ankle) at or above this counts as a straight body.
    public var minBodyLineAngle = 160.0
    /// Elbow angle at the top at or above this counts as extended arms.
    public var minTopElbowAngle = 155.0
    /// The elbow angle that is the clean target, shown in the text.
    public var idealElbowAngle = 90.0

    public init() {}

    public init(reference: AngleReference) {
        maxElbowAngle = reference.pushupElbowBottomMax
        minBodyLineAngle = reference.pushupBodyLineMin
        minTopElbowAngle = reference.pushupElbowTopMin
        idealElbowAngle = reference.pushupElbowIdeal
    }


    public func assess(bottomFrames: [PoseFrame]) -> TechniqueAssessment {
        assess(bottomFrames: bottomFrames, startFrames: [])
    }

    public func assess(bottomFrames: [PoseFrame], startFrames: [PoseFrame]) -> TechniqueAssessment {
        var measured = 0, deepEnough = 0, sagging = 0, piked = 0
        var elbows: [Double] = [], lines: [Double] = []
        for frame in bottomFrames {
            guard let side = Self.bestSide(frame) else { continue }
            measured += 1
            let elbow = frame.angle(side.shoulder, side.elbow, side.wrist)
            elbows.append(elbow)
            if elbow <= maxElbowAngle { deepEnough += 1 }
            if let hip = side.hip, let ankle = side.ankle {
                let line = frame.angle(side.shoulder, hip, ankle)
                lines.append(line)
                if line < minBodyLineAngle {
                    // Hip below the shoulder-ankle line = sagging (screen y grows downwards). The ratio of the x
                    // differences does not depend on the aspect ratio, so the plain coordinates are enough here.
                    let run = side.shoulder.x - ankle.x
                    let t = (hip.x - ankle.x) / (abs(run) < 1e-9 ? 1 : run)
                    let lineY = ankle.y + t * (side.shoulder.y - ankle.y)
                    if hip.y > lineY { sagging += 1 } else { piked += 1 }
                }
            }
        }
        guard measured > 0 else { return TechniqueAssessment(score: nil, findings: []) }

        let elbowText = elbows.isEmpty ? "" : " Najniżej łokcie: średnio \(degrees(average(elbows))) (cel ok. \(degrees(idealElbowAngle)))."
        let lineText = lines.isEmpty ? "" : " Kąt barki–biodra–kostki: średnio \(degrees(average(lines))) (prosta linia to 180°)."

        var findings: [TechniqueFinding] = []
        let shallow = measured - deepEnough
        findings.append(shallow == 0
            ? TechniqueFinding(id: "depth_ok", title: "Zakres ruchu",
                               detail: "Łokcie zginają się do około 90° w każdym powtórzeniu." + elbowText,
                               severity: .good, repsAffected: 0, repsTotal: measured)
            : TechniqueFinding(id: "pushup_shallow", title: "Za płytko",
                               detail: "Zejdź niżej, tak żeby łokcie zgięły się do około 90°." + elbowText,
                               severity: shallow * 2 > measured ? .major : .minor, repsAffected: shallow, repsTotal: measured))
        let bad = sagging + piked
        findings.append(bad == 0
            ? TechniqueFinding(id: "body_line_ok", title: "Linia ciała",
                               detail: "Ciało tworzy prostą linię od głowy do stóp." + lineText,
                               severity: .good, repsAffected: 0, repsTotal: measured)
            : TechniqueFinding(id: sagging >= piked ? "hips_sag" : "hips_high", title: "Linia ciała",
                               detail: (sagging >= piked ? "Biodra opadają. Napnij brzuch i pośladki, ciało w jednej linii."
                                                         : "Biodra są za wysoko. Opuść je, ciało w jednej linii.") + lineText,
                               severity: bad * 2 > measured ? .major : .minor, repsAffected: bad, repsTotal: measured))

        // The top of the movement: informational, it does not change the score.
        var tops: [Double] = []
        for frame in startFrames {
            if let side = Self.bestSide(frame) { tops.append(frame.angle(side.shoulder, side.elbow, side.wrist)) }
        }
        if !tops.isEmpty {
            let short = tops.filter { $0 < minTopElbowAngle }.count
            findings.append(short == 0
                ? TechniqueFinding(id: "lockout_ok", title: "Pozycja górna",
                                   detail: "Na górze ramiona są wyprostowane (średnio \(degrees(average(tops)))).",
                                   severity: .good, repsAffected: 0, repsTotal: tops.count)
                : TechniqueFinding(id: "pushup_no_lockout", title: "Pozycja górna",
                                   detail: "Na górze wyprostuj ramiona do końca (średnio \(degrees(average(tops))), cel od ok. \(degrees(minTopElbowAngle))).",
                                   severity: .minor, repsAffected: short, repsTotal: tops.count))
        }

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
/// approximated by the head being above the hands (which hold the bar) and the elbows being bent. With the start
/// frames (the hang) it also checks that the arms started from a full extension.
public struct BasicPullupAssessor: TechniqueAssessing {
    /// How far above the wrists (frame fraction) the nose must be.
    public var noseAboveWristsMargin = 0.02
    public var maxElbowAngle = 100.0
    /// Elbow angle in the hang at or above this counts as extended arms.
    public var minHangElbowAngle = 155.0

    public init() {}

    public init(reference: AngleReference) {
        noseAboveWristsMargin = reference.pullupNoseMargin
        maxElbowAngle = reference.pullupElbowTopMax
        minHangElbowAngle = reference.pullupElbowHangMin
    }


    public func assess(bottomFrames: [PoseFrame]) -> TechniqueAssessment {
        assess(bottomFrames: bottomFrames, startFrames: [])
    }

    public func assess(bottomFrames: [PoseFrame], startFrames: [PoseFrame]) -> TechniqueAssessment {
        var measured = 0, high = 0, bent = 0
        var elbows: [Double] = []
        for frame in bottomFrames {
            guard let nose = frame.joint(.nose) else { continue }
            let wrists = [frame.joint(.leftWrist), frame.joint(.rightWrist)].compactMap { $0 }
            guard let wristY = wrists.map(\.y).min() else { continue }
            measured += 1
            if nose.y < wristY - noseAboveWristsMargin { high += 1 }
            if let angle = Self.elbowAngle(frame) {
                elbows.append(angle)
                if angle <= maxElbowAngle { bent += 1 }
            }
        }
        guard measured > 0 else { return TechniqueAssessment(score: nil, findings: []) }

        let elbowText = elbows.isEmpty ? "" : " Łokcie na górze: średnio \(degrees(average(elbows))) (cel poniżej ok. \(degrees(maxElbowAngle)))."

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
            ? TechniqueFinding(id: "elbows_ok", title: "Praca łokci",
                               detail: "Łokcie zginają się w górnej pozycji." + elbowText,
                               severity: .good, repsAffected: 0, repsTotal: measured)
            : TechniqueFinding(id: "elbows_open", title: "Łokcie",
                               detail: "W górnej pozycji łokcie są prawie wyprostowane. Pociągnij łokcie w dół do boków." + elbowText,
                               severity: straight * 2 > measured ? .major : .minor, repsAffected: straight, repsTotal: measured))

        // The hang: informational, it does not change the score.
        let hangs = startFrames.compactMap { Self.elbowAngle($0) }
        if !hangs.isEmpty {
            let short = hangs.filter { $0 < minHangElbowAngle }.count
            findings.append(short == 0
                ? TechniqueFinding(id: "hang_ok", title: "Zwis", detail: "Każde powtórzenie zaczyna się z wyprostowanych ramion (średnio \(degrees(average(hangs)))).",
                                   severity: .good, repsAffected: 0, repsTotal: hangs.count)
                : TechniqueFinding(id: "pullup_partial_hang", title: "Zwis",
                                   detail: "Zacznij od pełnego zwisu, z wyprostowanymi ramionami (średnio \(degrees(average(hangs))), cel od ok. \(degrees(minHangElbowAngle))).",
                                   severity: .minor, repsAffected: short, repsTotal: hangs.count))
        }

        let highScore = 100.0 * Double(high) / Double(measured)
        let bentScore = 100.0 * Double(bent) / Double(measured)
        return TechniqueAssessment(score: Int((0.6 * highScore + 0.4 * bentScore).rounded()), findings: findings)
    }

    static func elbowAngle(_ frame: PoseFrame) -> Double? {
        func angle(_ s: JointName, _ e: JointName, _ w: JointName) -> (Double, Double)? {
            guard let sh = frame.joint(s), let el = frame.joint(e), let wr = frame.joint(w) else { return nil }
            return (frame.angle(sh, el, wr), min(sh.confidence, el.confidence, wr.confidence))
        }
        let sides = [angle(.leftShoulder, .leftElbow, .leftWrist), angle(.rightShoulder, .rightElbow, .rightWrist)].compactMap { $0 }
        return sides.max(by: { $0.1 < $1.1 })?.0
    }
}

/// Dip on parallel bars from a side view, judged at the lowest point of each repetition: how far the elbows bent
/// (the upper arm about parallel to the floor or lower) and, with the start frames, whether the arms were locked out
/// at the top. How deep is too deep and the torso lean are reported but do not change the score: they depend on
/// the person's shoulder mobility and on the style (leaning forward works the chest more, upright the triceps).
/// Thresholds come from `AngleReference` (sources in docs/ANALIZA_TECHNIKI.md).
public struct BasicDipAssessor: TechniqueAssessing {
    /// Elbow angle at or below this counts as a full range (upper arm about parallel to the floor).
    public var maxElbowAngle = 100.0
    /// Elbow angle below this is flagged as very deep.
    public var deepElbowAngle = 45.0
    /// Elbow angle at the top at or above this counts as a lockout.
    public var minTopElbowAngle = 155.0

    public init() {}

    public init(reference: AngleReference) {
        maxElbowAngle = reference.dipElbowBottomMax
        deepElbowAngle = reference.dipElbowDeepMin
        minTopElbowAngle = reference.dipElbowTopMin
    }

    public func assess(bottomFrames: [PoseFrame]) -> TechniqueAssessment {
        assess(bottomFrames: bottomFrames, startFrames: [])
    }

    public func assess(bottomFrames: [PoseFrame], startFrames: [PoseFrame]) -> TechniqueAssessment {
        var measured = 0, deepEnough = 0, veryDeep = 0
        var elbows: [Double] = [], leans: [Double] = []
        for frame in bottomFrames {
            guard let arm = PoseLimbs.arm(in: frame, minConfidence: 0.15) else { continue }
            measured += 1
            let elbow = arm.elbowAngle(in: frame)
            elbows.append(elbow)
            if elbow <= maxElbowAngle { deepEnough += 1 }
            if elbow < deepElbowAngle { veryDeep += 1 }
            if let neck = frame.joint(.neck, minConfidence: 0.15) ?? frame.joint(.leftShoulder, minConfidence: 0.15),
               let root = frame.joint(.root, minConfidence: 0.15) ?? frame.joint(.leftHip, minConfidence: 0.15) {
                leans.append(frame.angleFromVertical(from: root, to: neck))
            }
        }
        guard measured > 0 else { return TechniqueAssessment(score: nil, findings: []) }

        let elbowText = " Najniżej łokcie: średnio \(degrees(average(elbows))) (cel do ok. \(degrees(maxElbowAngle)))."
        var findings: [TechniqueFinding] = []
        let shallow = measured - deepEnough
        findings.append(shallow == 0
            ? TechniqueFinding(id: "depth_ok", title: "Zakres ruchu",
                               detail: "Barki schodzą do poziomu łokci lub niżej w każdym powtórzeniu." + elbowText,
                               severity: .good, repsAffected: 0, repsTotal: measured)
            : TechniqueFinding(id: "dip_shallow", title: "Za płytko",
                               detail: "Zejdź niżej, tak żeby ramię było w dolnej pozycji mniej więcej równolegle do podłogi." + elbowText,
                               severity: shallow * 2 > measured ? .major : .minor, repsAffected: shallow, repsTotal: measured))

        // Informational: very deep dips load the front of the shoulder more. A signal, not a verdict.
        if veryDeep > 0 {
            findings.append(TechniqueFinding(id: "dip_very_deep", title: "Bardzo głęboko",
                                             detail: "Łokcie zginają się poniżej ok. \(degrees(deepElbowAngle)). Głębsze zejście mocniej obciąża przód barku. Zatrzymaj się wyżej, jeśli czujesz tam dyskomfort.",
                                             severity: .minor, repsAffected: veryDeep, repsTotal: measured))
        }

        // The top of the movement: a lockout is part of a full repetition.
        var tops: [Double] = []
        for frame in startFrames {
            if let arm = PoseLimbs.arm(in: frame, minConfidence: 0.15) { tops.append(arm.elbowAngle(in: frame)) }
        }
        var lockedOut = tops.count
        if !tops.isEmpty {
            let short = tops.filter { $0 < minTopElbowAngle }.count
            lockedOut = tops.count - short
            findings.append(short == 0
                ? TechniqueFinding(id: "lockout_ok", title: "Pozycja górna",
                                   detail: "Na górze ramiona są wyprostowane (średnio \(degrees(average(tops)))).",
                                   severity: .good, repsAffected: 0, repsTotal: tops.count)
                : TechniqueFinding(id: "dip_no_lockout", title: "Pozycja górna",
                                   detail: "Na górze wyprostuj ramiona do końca (średnio \(degrees(average(tops))), cel od ok. \(degrees(minTopElbowAngle))).",
                                   severity: short * 2 > tops.count ? .major : .minor, repsAffected: short, repsTotal: tops.count))
        }

        // The lean does not change the score: it only says which muscles do more of the work.
        if !leans.isEmpty {
            let lean = average(leans)
            findings.append(TechniqueFinding(id: "torso_lean_info", title: "Pochylenie tułowia",
                                             detail: lean >= 25
                                                 ? "Tułów pochylony średnio o \(degrees(lean)) od pionu: to ustawienie mocniej pracuje klatką. Bardziej pionowo mocniej pracują triceps."
                                                 : "Tułów prawie pionowo (średnio \(degrees(lean)) od pionu): mocniej pracują triceps. Pochylenie do przodu przesuwa pracę na klatkę.",
                                             severity: .good, repsAffected: 0, repsTotal: leans.count))
        }

        let depthScore = 100.0 * Double(deepEnough) / Double(measured)
        guard !tops.isEmpty else { return TechniqueAssessment(score: Int(depthScore.rounded()), findings: findings) }
        let lockoutScore = 100.0 * Double(lockedOut) / Double(tops.count)
        return TechniqueAssessment(score: Int((0.6 * depthScore + 0.4 * lockoutScore).rounded()), findings: findings)
    }
}
