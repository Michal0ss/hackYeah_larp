import Foundation
import Contracts

/// How mobile a person says they are in one region of the body. Their own answer, not a measurement or a diagnosis.
public enum Mobility: String, Codable, CaseIterable, Sendable {
    case limited, typical, good

    public var title: String {
        switch self {
        case .limited: return "Ograniczona"
        case .typical: return "Przeciętna"
        case .good: return "Dobra"
        }
    }
}

/// What the assessment may take into account about the person besides the pose in the video: how mobile they are, how
/// experienced, and whether an earlier injury calls for not pushing the range of a movement.
///
/// One rule holds for everything here: **context only widens the limits, it never narrows them.** The standard ranges
/// (`AngleReference`, sources in docs/ANALIZA_TECHNIKI.md) are the full-credit criteria; a person with a reason gets a
/// wider band, and nobody gets a stricter one than the standard. The context stays on the phone (it contains what the
/// person said about their body and, through `lowerBodyCaution` and `upperBodyCaution`, a trace of their health
/// history): it is never sent to the backend and never stored in a result.
public struct TechniqueContext: Equatable, Sendable {
    /// Ankles and hips: what limits the depth of a squat and how far the torso has to lean.
    public var lowerBodyMobility: Mobility
    /// Shoulders: what limits how deep a dip goes.
    public var shoulderMobility: Mobility
    public var level: TrainingLevel
    /// A knee, hip or ankle injury that is not old: the range of a squat is not pushed.
    public var lowerBodyCaution: Bool
    /// A shoulder or elbow injury that is not old: the range of a push-up, pull-up and dip is not pushed.
    public var upperBodyCaution: Bool

    public init(lowerBodyMobility: Mobility = .typical, shoulderMobility: Mobility = .typical,
                level: TrainingLevel = .intermediate, lowerBodyCaution: Bool = false, upperBodyCaution: Bool = false) {
        self.lowerBodyMobility = lowerBodyMobility
        self.shoulderMobility = shoulderMobility
        self.level = level
        self.lowerBodyCaution = lowerBodyCaution
        self.upperBodyCaution = upperBodyCaution
    }

    /// No allowances: the standard ranges.
    public static let standard = TechniqueContext()
}

/// How much each reason widens a limit. Starting values to be tuned on real recordings (docs/ANALIZA_TECHNIKI.md, section
/// "Kontekst osoby"); loaded from `content/config/scoring.json`, section "context". Negative values are ignored: a
/// reason can only widen.
public struct ContextRules: Equatable, Sendable {
    // Squat: degrees on the knee angle bands (parallel and deep), fraction of the image height on the depth test,
    // degrees on the torso lean limit.
    public var kneeExtraLimited = 12.0
    public var kneeExtraCaution = 12.0
    public var kneeExtraMax = 20.0
    public var depthToleranceExtraLimited = 0.02
    public var depthToleranceExtraCaution = 0.02
    public var depthToleranceExtraBeginner = 0.01
    public var depthToleranceExtraMax = 0.04
    public var torsoLeanExtraLimited = 5.0
    public var torsoLeanExtraBeginner = 3.0
    public var torsoLeanExtraMax = 8.0
    /// Proportions measured in the pose: thigh length over torso length. A thigh longer than the reference needs more
    /// forward lean to keep the balance over the feet, so the lean limit grows by `torsoLeanPerRatio` degrees for every
    /// 1.0 of ratio above `thighToTorsoReference`, up to `torsoLeanProportionMax`.
    public var thighToTorsoReference = 0.85
    public var torsoLeanPerRatio = 60.0
    public var torsoLeanProportionMax = 8.0
    // Push-up, pull-up, dip: degrees on the elbow limit.
    public var elbowExtraBeginner = 5.0
    public var elbowExtraCaution = 10.0
    public var dipElbowExtraLimited = 10.0
    public var elbowExtraMax = 15.0
    // Scoring a recorded squat: degrees of spread between repetitions that still count as repeatable.
    public var repeatabilityExtraBeginner = 5.0

    public init() {}

    /// Values from `content/config/scoring.json` (section "context"). Missing keys keep their defaults.
    public init(values: [String: Double]) {
        self.init()
        func widen(_ key: String, _ current: Double) -> Double { max(0, values[key] ?? current) }
        kneeExtraLimited = widen("kneeExtraLimited", kneeExtraLimited)
        kneeExtraCaution = widen("kneeExtraCaution", kneeExtraCaution)
        kneeExtraMax = widen("kneeExtraMax", kneeExtraMax)
        depthToleranceExtraLimited = widen("depthToleranceExtraLimited", depthToleranceExtraLimited)
        depthToleranceExtraCaution = widen("depthToleranceExtraCaution", depthToleranceExtraCaution)
        depthToleranceExtraBeginner = widen("depthToleranceExtraBeginner", depthToleranceExtraBeginner)
        depthToleranceExtraMax = widen("depthToleranceExtraMax", depthToleranceExtraMax)
        torsoLeanExtraLimited = widen("torsoLeanExtraLimited", torsoLeanExtraLimited)
        torsoLeanExtraBeginner = widen("torsoLeanExtraBeginner", torsoLeanExtraBeginner)
        torsoLeanExtraMax = widen("torsoLeanExtraMax", torsoLeanExtraMax)
        thighToTorsoReference = values["thighToTorsoReference"].map { max(0.3, $0) } ?? thighToTorsoReference
        torsoLeanPerRatio = widen("torsoLeanPerRatio", torsoLeanPerRatio)
        torsoLeanProportionMax = widen("torsoLeanProportionMax", torsoLeanProportionMax)
        elbowExtraBeginner = widen("elbowExtraBeginner", elbowExtraBeginner)
        elbowExtraCaution = widen("elbowExtraCaution", elbowExtraCaution)
        dipElbowExtraLimited = widen("dipElbowExtraLimited", dipElbowExtraLimited)
        elbowExtraMax = widen("elbowExtraMax", elbowExtraMax)
        repeatabilityExtraBeginner = widen("repeatabilityExtraBeginner", repeatabilityExtraBeginner)
    }
}

/// The standard ranges with one person's allowances added, and the sentences that tell them what was adapted.
public struct ContextAdjustment: Equatable, Sendable {
    /// The reference to assess with.
    public var reference: AngleReference
    /// Degrees added to the squat torso lean limit (mobility, level and proportions together), so a scorer that keeps
    /// its own copy of that limit can follow.
    public var torsoLeanExtra: Double
    /// Degrees added to the spread between repetitions that still counts as repeatable.
    public var repeatabilityExtra: Double
    /// What was adapted, in Polish, for the person to read. Empty when the standard applies.
    public var notes: [String]

    public var isStandard: Bool { notes.isEmpty }
}

public extension TechniqueContext {
    /// The allowances for `kind`. `thighToTorso` is the proportion measured in the pose (`BodyProportions`); nil when
    /// it was not measured. Never narrower than `base`.
    func adjustment(for kind: MovementKind, base: AngleReference, rules: ContextRules = ContextRules(),
                    thighToTorso: Double? = nil) -> ContextAdjustment {
        var reference = base
        var notes: [String] = []
        var torsoLeanExtra = 0.0
        var repeatabilityExtra = 0.0
        let beginner = level == .beginner

        switch kind {
        case .squat:
            var knee = 0.0, depth = 0.0, lean = 0.0
            if lowerBodyMobility == .limited {
                knee += rules.kneeExtraLimited
                depth += rules.depthToleranceExtraLimited
                lean += rules.torsoLeanExtraLimited
                notes.append("Mobilność nóg i bioder: ograniczona. Zakres zejścia i pochylenia tułowia jest dla Ciebie szerszy.")
            }
            if lowerBodyCaution {
                knee += rules.kneeExtraCaution
                depth += rules.depthToleranceExtraCaution
                notes.append("Uwzględniamy Twoją historię kontuzji: nie wymagamy pełnej głębokości. Nie forsuj ruchu, jeśli coś boli.")
            }
            if beginner {
                depth += rules.depthToleranceExtraBeginner
                lean += rules.torsoLeanExtraBeginner
                repeatabilityExtra += rules.repeatabilityExtraBeginner
                notes.append("Poziom początkujący: granice techniki są nieco szersze.")
            }
            knee = min(knee, rules.kneeExtraMax)
            depth = min(depth, rules.depthToleranceExtraMax)
            lean = min(lean, rules.torsoLeanExtraMax)
            if let ratio = thighToTorso {
                let byProportions = min(rules.torsoLeanProportionMax,
                                        max(0, (ratio - rules.thighToTorsoReference) * rules.torsoLeanPerRatio))
                if byProportions >= 1 {
                    notes.append("Granica pochylenia tułowia uwzględnia Twoje proporcje (długość uda względem tułowia, z nagrania).")
                }
                lean += byProportions
            }
            reference.squatKneeParallelMax += knee
            reference.squatKneeDeepMax += knee
            reference.squatDepthTolerance += depth
            reference.squatTorsoLeanMax += lean
            torsoLeanExtra = lean

        case .pushup, .pullup, .dip:
            var elbow = 0.0
            if beginner {
                elbow += rules.elbowExtraBeginner
                notes.append("Poziom początkujący: granice techniki są nieco szersze.")
            }
            if upperBodyCaution {
                elbow += rules.elbowExtraCaution
                notes.append("Uwzględniamy Twoją historię kontuzji: nie wymagamy pełnego zakresu. Nie forsuj ruchu, jeśli coś boli.")
            }
            if kind == .dip, shoulderMobility == .limited {
                elbow += rules.dipElbowExtraLimited
                notes.append("Mobilność barków: ograniczona. Zakres zejścia w dipach jest dla Ciebie szerszy.")
            }
            elbow = min(elbow, rules.elbowExtraMax)
            switch kind {
            case .pushup: reference.pushupElbowBottomMax += elbow
            case .pullup: reference.pullupElbowTopMax += elbow
            default: reference.dipElbowBottomMax += elbow
            }
        }
        return ContextAdjustment(reference: reference, torsoLeanExtra: torsoLeanExtra,
                                 repeatabilityExtra: repeatabilityExtra, notes: notes)
    }
}

/// Body proportions that can be read from the pose itself. Height does not help the assessment (an angle is the same
/// for a short and a tall person); the length of the thigh against the torso does: it decides how far a person has to
/// lean forward in a squat.
public enum BodyProportions {
    /// Thigh length (hip to knee) divided by torso length (neck to hip): the median over the frames in which the leg
    /// and the neck are seen. Both are measured on the same side, in image-height units. Frames with a ratio no human
    /// has are dropped as tracking errors. Nil when fewer than `minFrames` frames qualify.
    public static func thighToTorso(in frames: [PoseFrame], minConfidence: Double = 0.3, minFrames: Int = 3) -> Double? {
        median(of: ratios(in: frames, minConfidence: minConfidence), atLeast: minFrames)
    }

    static func ratios(in frames: [PoseFrame], minConfidence: Double = 0.3) -> [Double] {
        frames.compactMap { frame in
            guard let leg = PoseLimbs.leg(in: frame, minConfidence: minConfidence),
                  let neck = frame.joint(.neck, minConfidence: minConfidence) else { return nil }
            let thigh = frame.distance(leg.hip, leg.knee)
            let torso = frame.distance(neck, leg.hip)
            guard thigh > 0.02, torso > 0.02 else { return nil }
            let ratio = thigh / torso
            return (0.5...1.4).contains(ratio) ? ratio : nil
        }
    }

    static func median(of values: [Double], atLeast minimum: Int) -> Double? {
        guard values.count >= max(1, minimum) else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

/// Assesses with the person's context: the same assessor as the standard one, with the ranges widened by what the
/// context allows. Used by the live set, so a set and a recorded clip are judged by the same rules.
///
/// For a squat the proportions are measured from the frames it is given. It remembers the proportions of the whole set
/// (a repetition is judged on two frames, too few to measure), so the verdict on later repetitions and the summary use
/// the same number.
public final class ContextualAssessor: TechniqueAssessing, @unchecked Sendable {
    private static let memoryLimit = 300

    private let kind: MovementKind
    private let base: AngleReference
    private let context: TechniqueContext
    private let rules: ContextRules
    private let lock = NSLock()
    private var seenRatios: [Double] = []

    public init(kind: MovementKind, base: AngleReference, context: TechniqueContext, rules: ContextRules = ContextRules()) {
        self.kind = kind
        self.base = base
        self.context = context
        self.rules = rules
    }

    public func assess(bottomFrames: [PoseFrame]) -> TechniqueAssessment {
        assess(bottomFrames: bottomFrames, startFrames: [])
    }

    public func assess(bottomFrames: [PoseFrame], startFrames: [PoseFrame]) -> TechniqueAssessment {
        let ratio = kind == .squat ? remember(startFrames + bottomFrames) : nil
        let adjusted = context.adjustment(for: kind, base: base, rules: rules, thighToTorso: ratio)
        return kind.assessor(reference: adjusted.reference).assess(bottomFrames: bottomFrames, startFrames: startFrames)
    }

    /// Adds the proportions of these frames to what the set showed so far; the median of all of it, once it is enough.
    private func remember(_ frames: [PoseFrame]) -> Double? {
        let new = BodyProportions.ratios(in: frames)
        lock.lock()
        defer { lock.unlock() }
        seenRatios.append(contentsOf: new)
        if seenRatios.count > Self.memoryLimit { seenRatios.removeFirst(seenRatios.count - Self.memoryLimit) }
        return BodyProportions.median(of: seenRatios, atLeast: 3)
    }
}
