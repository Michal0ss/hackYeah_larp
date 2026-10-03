import Contracts
import Foundation

/// A short, human description of where the coach was opened from, shown at the top of the chat so the user sees what
/// the trainer knows about the moment (the same numbers that travel in `WorkoutContext`, nothing more).
public struct WorkoutContextSummary: Equatable, Sendable {
    /// "Seria na żywo", "Odpoczynek między seriami", ...
    public var title: String
    /// One short line each: the workout, the exercise and set, the last set.
    public var lines: [String]

    public static func make(for context: WorkoutContext, sessionTitle: String?, exerciseName: String?) -> WorkoutContextSummary {
        var lines: [String] = []
        if let sessionTitle { lines.append("Trening: \(sessionTitle)") }
        if let exerciseName {
            var line = "Ćwiczenie: \(exerciseName)"
            if let index = context.setIndex, let total = context.totalSets { line += " · seria \(index) z \(total)" }
            lines.append(line)
        }
        if let digest = context.lastSet {
            var parts = ["\(digest.reps) powt."]
            if let technique = digest.techniqueScore { parts.append("technika \(technique)/100") }
            parts.append("tempo \(digest.tempoScore)/100")
            lines.append("Ostatnia seria: " + parts.joined(separator: ", "))
        } else if let logged = context.loggedSet {
            var parts: [String] = []
            if let reps = logged.reps { parts.append("\(reps) powt.") }
            if let seconds = logged.seconds { parts.append("\(seconds) s") }
            if let weight = logged.weightKg { parts.append(weightText(weight)) }
            if !parts.isEmpty { lines.append("Ostatnia seria: " + parts.joined(separator: ", ")) }
        }
        return WorkoutContextSummary(title: title(for: context.screen), lines: lines)
    }

    static func title(for screen: WorkoutScreen) -> String {
        switch screen {
        case .today: return "Pytasz z ekranu Dziś"
        case .plan: return "Pytasz przed treningiem"
        case .liveSet: return "Pytasz w trakcie serii"
        case .setSummary: return "Pytasz po serii"
        case .rest: return "Pytasz podczas odpoczynku"
        case .sessionFeedback: return "Pytasz po treningu"
        case .analysis: return "Pytasz po analizie techniki"
        }
    }

    private static func weightText(_ kg: Double) -> String {
        (kg == kg.rounded() ? String(Int(kg)) : String(format: "%.1f", kg).replacingOccurrences(of: ".", with: ",")) + " kg"
    }
}
