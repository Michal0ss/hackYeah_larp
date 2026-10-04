import Foundation
import Contracts

/// The exercises the live coach can follow. Each one is reduced to the same single number ("depth": how far the
/// body is from its starting position, in torso lengths, growing while the movement goes away from the start),
/// so one phase tracker and one tempo coach serve all of them.
///
/// - squat: hips go down.
/// - pushup (side view, camera low): the neck/shoulders go down towards the floor.
/// - dip (side view, supported on parallel bars): the shoulders go down between the hands, like a push-up turned
///   upright. Tracked exactly like the push-up (neck/shoulders down = away from the start, arms locked out).
/// - pullup (front or side view, hanging from a bar): the neck/shoulders go UP. Here the first part of a
///   repetition is the pull (concentric) and the way back is the lowering (eccentric), so phases are swapped
///   after tracking (`exercisePhase`). In the tempo spec "bottomPause" is the pause at the far end of the
///   movement: at the bottom of a squat or push-up, at the top of a pull-up.
public enum MovementKind: String, Codable, CaseIterable, Sendable {
    case squat, pushup, pullup, dip

    /// Which live movement fits a catalog exercise, nil when the live coach cannot follow it.
    public static func kind(for exercise: ExerciseItem) -> MovementKind? {
        if exercise.id.contains("pullup") || exercise.id.contains("chinup") { return .pullup }
        if exercise.id.contains("pushup") { return .pushup }
        if exercise.id == "dip" || exercise.id.hasSuffix("_dip") { return .dip }
        if exercise.pattern == "squat" || exercise.id.contains("squat") { return .squat }
        return nil
    }

    public var title: String {
        switch self {
        case .squat: return "Przysiad"
        case .pushup: return "Pompka"
        case .pullup: return "Podciąganie"
        case .dip: return "Dipy"
        }
    }

    /// True when the part of the repetition that moves away from the start is the concentric one.
    public var isReversed: Bool { self == .pullup }

    /// Elbow angle in the start position below which a repetition found in a recorded clip does not count: a person who
    /// is still getting onto the bars (or stepping off) bends and straightens the arms without doing a repetition.
    /// Nil = no such rule (the other exercises keep counting every full movement).
    public var minStartElbowForClip: Double? { self == .dip ? 145 : nil }

    /// Where the phone goes and what the person does, shown while framing.
    public var setupHint: String {
        switch self {
        case .squat: return "Postaw telefon bokiem do siebie, na wysokości bioder, 2–3 m od siebie. Załóż słuchawki."
        case .pushup: return "Postaw telefon na podłodze bokiem do siebie, 2–3 m od stóp. Cała sylwetka od głowy do stóp ma być w kadrze. Załóż słuchawki."
        case .pullup: return "Postaw telefon przed drążkiem lub z boku, na wysokości klatki, 2–3 m od siebie. Ma być widać głowę, ręce na drążku i biodra. Załóż słuchawki."
        case .dip: return "Postaw telefon bokiem do siebie, na wysokości łokci, 2–3 m od poręczy. Ma być widać głowę, ręce na poręczy, biodra i kolana. Załóż słuchawki."
        }
    }

    public var calibrationTitle: String {
        switch self {
        case .squat: return "Stój prosto i nieruchomo"
        case .pushup: return "Przyjmij pozycję górną i nie ruszaj się"
        case .pullup: return "Zawiśnij na wyprostowanych rękach"
        case .dip: return "Podeprzyj się na wyprostowanych rękach"
        }
    }

    public var calibrationSpoken: String {
        switch self {
        case .squat: return "Stań prosto i nieruchomo"
        case .pushup: return "Przyjmij pozycję górną i zastygnij"
        case .pullup: return "Zawiśnij na wyprostowanych rękach i zastygnij"
        case .dip: return "Podeprzyj się na wyprostowanych rękach i zastygnij"
        }
    }

    /// Maps what the tracker saw (movement away from / back to the start) to the exercise's own phase.
    func exercisePhase(_ tracked: RepPhase) -> RepPhase {
        guard isReversed else { return tracked }
        switch tracked {
        case .eccentric: return .concentric
        case .concentric: return .eccentric
        case .bottomPause, .topPause: return tracked
        }
    }

    /// Public: Analysis reuses this to match the live set's eccentric/concentric swap for pull-ups.
    public func exerciseRep(_ tracked: RepTempo) -> RepTempo {
        guard isReversed else { return tracked }
        var rep = tracked
        rep.eccentric = tracked.concentric
        rep.concentric = tracked.eccentric
        return rep
    }

    /// Public: Analysis scores push-up/pull-up with the exact same assessor the live set uses, so a
    /// file analysis and a live set never show two different scores for the same exercise.
    public var defaultAssessor: TechniqueAssessing { assessor(reference: AngleReference()) }

    /// The assessor with the angle ranges of `reference` (from `content/config/scoring.json`, section "angles").
    public func assessor(reference: AngleReference) -> TechniqueAssessing {
        switch self {
        case .squat: return BasicSquatAssessor(reference: reference)
        case .pushup: return BasicPushupAssessor(reference: reference)
        case .pullup: return BasicPullupAssessor(reference: reference)
        case .dip: return BasicDipAssessor(reference: reference)
        }
    }
}
