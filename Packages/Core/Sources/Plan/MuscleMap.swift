import Contracts
import Foundation

/// Muscle regions shown on the body figure. Coarse on purpose: what the figure can draw and a person can recognise.
public enum Muscle: String, CaseIterable, Codable, Sendable {
    case chest, shoulders, biceps, triceps, upperBack, lats, lowerBack, abs, obliques, glutes, quads, hamstrings, calves

    public var title: String {
        switch self {
        case .chest: return "Klatka piersiowa"
        case .shoulders: return "Barki"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .upperBack: return "Górne plecy"
        case .lats: return "Plecy (najszersze)"
        case .lowerBack: return "Dolne plecy"
        case .abs: return "Brzuch"
        case .obliques: return "Boki brzucha"
        case .glutes: return "Pośladki"
        case .quads: return "Przód uda"
        case .hamstrings: return "Tył uda"
        case .calves: return "Łydki"
        }
    }
}

/// How much a muscle works in an exercise or a whole session.
public enum MuscleLoad: Int, Comparable, Sendable {
    /// Helps the movement.
    case secondary = 1
    /// Does most of the work.
    case primary = 2

    public static func < (lhs: MuscleLoad, rhs: MuscleLoad) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Which muscles an exercise works, from the catalog id (a hand-made table: the catalog only has a coarse group name)
/// and, for an exercise the table does not know, from that group name. Not a measurement: a general description of
/// the movement.
public enum MuscleMap {
    public typealias Activation = [Muscle: MuscleLoad]

    private static let table: [String: Activation] = {
        let squat: Activation = [.quads: .primary, .glutes: .primary, .hamstrings: .secondary, .calves: .secondary, .abs: .secondary]
        let lunge: Activation = [.quads: .primary, .glutes: .primary, .hamstrings: .secondary, .calves: .secondary]
        let pushup: Activation = [.chest: .primary, .shoulders: .secondary, .triceps: .secondary, .abs: .secondary]
        let bridge: Activation = [.glutes: .primary, .hamstrings: .secondary, .lowerBack: .secondary]
        let bench: Activation = [.chest: .primary, .triceps: .secondary, .shoulders: .secondary]
        return [
            "squat": squat, "goblet_squat": squat, "box_squat": squat, "back_squat": squat, "jump_squat": squat,
            "leg_press": [.quads: .primary, .glutes: .secondary, .hamstrings: .secondary],
            "lunge": lunge, "split_squat": lunge, "step_up": lunge,
            "glute_bridge": bridge, "hip_thrust": bridge,
            "romanian_deadlift": [.hamstrings: .primary, .glutes: .primary, .lowerBack: .secondary],
            "barbell_deadlift": [.hamstrings: .primary, .glutes: .primary, .lowerBack: .primary, .upperBack: .secondary, .quads: .secondary],
            "pushup": pushup, "incline_pushup": pushup, "weighted_pushup": pushup,
            "bench_press": bench, "dumbbell_bench_press": bench,
            "overhead_press": [.shoulders: .primary, .triceps: .secondary, .upperBack: .secondary],
            "lateral_raise": [.shoulders: .primary],
            "dip": [.chest: .primary, .triceps: .primary, .shoulders: .secondary],
            "dumbbell_row": [.lats: .primary, .upperBack: .primary, .biceps: .secondary],
            "lat_pulldown": [.lats: .primary, .biceps: .secondary, .upperBack: .secondary],
            "pullup": [.lats: .primary, .biceps: .primary, .upperBack: .secondary, .abs: .secondary],
            "superman": [.lowerBack: .primary, .glutes: .secondary, .upperBack: .secondary],
            "plank": [.abs: .primary, .obliques: .secondary, .shoulders: .secondary, .glutes: .secondary],
            "dead_bug": [.abs: .primary, .obliques: .secondary],
            "side_plank": [.obliques: .primary, .abs: .secondary, .glutes: .secondary, .shoulders: .secondary],
            "marching": [.quads: .secondary, .abs: .secondary, .calves: .secondary],
            "jumping_jacks": [.calves: .secondary, .shoulders: .secondary, .quads: .secondary],
        ]
    }()

    /// The muscles of one exercise. `muscleGroup` is the catalog's group name ("Klatka, barki"), used only when the
    /// table does not know the id.
    public static func activation(exerciseId: String, muscleGroup: String? = nil) -> Activation {
        if let known = table[exerciseId] { return known }
        let group = (muscleGroup ?? "").folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        var result: Activation = [:]
        func add(_ muscles: [Muscle], _ load: MuscleLoad) { for m in muscles { result[m] = max(result[m] ?? load, load) } }
        if group.contains("klatk") { add([.chest], .primary) }
        if group.contains("bark") { add([.shoulders], .primary) }
        if group.contains("triceps") { add([.triceps], .primary) }
        if group.contains("ramion") { add([.biceps], .primary) }
        if group.contains("plecy") { add([.lats, .upperBack], .primary) }
        if group.contains("brzuch") { add([.abs], .primary) }
        if group.contains("bok") { add([.obliques], .primary) }
        if group.contains("posladk") { add([.glutes], .primary) }
        if group.contains("uda") { add([.hamstrings], .primary) }
        if group.contains("nogi") { add([.quads, .glutes], .primary); add([.hamstrings, .calves], .secondary) }
        if group.contains("ciał") || group.contains("cial") { add([.quads, .abs, .shoulders, .calves], .secondary) }
        return result
    }

    /// The muscles of a whole session: the strongest role any of its exercises gives each muscle.
    public static func activation(for session: PlannedSession, catalog: (String) -> ExerciseItem?) -> Activation {
        var result: Activation = [:]
        for planned in session.exercises {
            let one = activation(exerciseId: planned.exerciseId, muscleGroup: catalog(planned.exerciseId)?.muscleGroup)
            for (muscle, load) in one { result[muscle] = max(result[muscle] ?? load, load) }
        }
        return result
    }
}
