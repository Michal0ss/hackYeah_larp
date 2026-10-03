import Contracts
import Foundation

/// The questions behind the "Przeprowadź mnie" buttons of a workout: the AI trainer walks the user through the
/// session (or one exercise) and explains everything. Only the plan goes into the text: exercise names, sets,
/// repetitions, rest and tempo. No health data.
public enum WorkoutGuide {
    /// Asked for one exercise, e.g. from the screen of a set.
    public static let explainExerciseQuestion = "Wytłumacz to ćwiczenie krok po kroku"

    /// One exercise of the session as the guide sees it.
    public struct Entry: Equatable, Sendable {
        public var name: String
        public var planned: PlannedExercise
        /// Counted in seconds, not repetitions (e.g. a plank).
        public var timed: Bool
        /// The camera follows this exercise (the live coach).
        public var live: Bool

        public init(name: String, planned: PlannedExercise, timed: Bool = false, live: Bool = false) {
            self.name = name
            self.planned = planned
            self.timed = timed
            self.live = live
        }
    }

    /// "Przeprowadź mnie przez trening": the whole session, in order, from `startExercise` on.
    public static func sessionQuestion(title: String, entries: [Entry]) -> String {
        var lines = ["Przeprowadź mnie przez ten trening („\(title)”) od początku do końca i wszystko dokładnie wyjaśnij."]
        lines.append("Ćwiczenia po kolei:")
        for (index, entry) in entries.enumerated() {
            lines.append("\(index + 1). \(entry.name): \(target(entry)), przerwa \(entry.planned.restSeconds) s"
                         + (tempoText(entry.planned.tempo).map { ", tempo \($0)" } ?? ""))
        }
        lines.append("Na początek powiedz, jak się rozgrzać i czego się spodziewać. Potem przy każdym ćwiczeniu: "
                     + "pozycja startowa, jak wykonać ruch, jak oddychać, co czuć i na co uważać, "
                     + "jak rozumieć serie, powtórzenia, przerwę i tempo. Na końcu powiedz, jak skończyć trening.")
        return lines.joined(separator: "\n")
    }

    /// "Wytłumacz to ćwiczenie": one exercise, with its numbers from the plan.
    public static func exerciseQuestion(_ entry: Entry) -> String {
        var text = "Wytłumacz mi dokładnie ćwiczenie „\(entry.name)” (\(target(entry))"
        text += ", przerwa \(entry.planned.restSeconds) s"
        if let tempo = tempoText(entry.planned.tempo) { text += ", tempo \(tempo)" }
        text += "): pozycja startowa, jak wykonać ruch, jak oddychać, na co uważać i jak rozumieć te liczby."
        return text
    }

    // MARK: text

    private static func target(_ entry: Entry) -> String {
        let planned = entry.planned
        let range = planned.repsMin == planned.repsMax ? "\(planned.repsMax)" : "\(planned.repsMin)–\(planned.repsMax)"
        return "\(planned.sets) × \(range)" + (entry.timed ? " s" : " powt.")
    }

    /// 3-1-2-0: seconds down, pause at the bottom, up, pause at the top.
    static func tempoText(_ tempo: TempoSpec?) -> String? {
        guard let tempo else { return nil }
        return [tempo.eccentric, tempo.bottomPause, tempo.concentric, tempo.topPause].map(seconds).joined(separator: "-")
    }

    private static func seconds(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}
