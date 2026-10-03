import Foundation
import Contracts

public struct SpokenCue: Equatable, Sendable {
    /// Seconds after the start of the phase.
    public var offset: Double
    public var text: String

    public init(offset: Double, text: String) {
        self.offset = offset
        self.text = text
    }
}

/// Plans the counting that is spoken during a phase: "jeden, dwa, trzy" once per second.
public enum CuePlanner {
    public static let words = ["jeden", "dwa", "trzy", "cztery", "pięć", "sześć", "siedem", "osiem"]

    public static func duration(of phase: RepPhase, in spec: TempoSpec) -> Double {
        switch phase {
        case .eccentric: return spec.eccentric
        case .bottomPause: return spec.bottomPause
        case .concentric: return spec.concentric
        case .topPause: return spec.topPause
        }
    }

    /// Spoken name of the phase, said together with the first count of the first repetition.
    public static func label(of phase: RepPhase) -> String {
        switch phase {
        case .eccentric: return "w dół"
        case .bottomPause: return "trzymaj"
        case .concentric: return "w górę"
        case .topPause: return "stop"
        }
    }

    public static func cues(for phase: RepPhase, spec: TempoSpec, isFirstRep: Bool) -> [SpokenCue] {
        let count = min(Int(duration(of: phase, in: spec).rounded()), words.count)
        guard count > 0 else { return [] }
        return (0..<count).map { i in
            let text = (isFirstRep && i == 0) ? "\(label(of: phase)), \(words[i])" : words[i]
            return SpokenCue(offset: Double(i), text: text)
        }
    }
}

/// Short spoken corrections between repetitions. At most one per repetition, with a cooldown.
public struct CoachingPolicy {
    public var cooldownReps = 2
    private var repsSinceAdvice = 99
    private var onTempoStreak = 0

    public init() {}

    public mutating func advice(after rep: RepTempo, spec: TempoSpec) -> String? {
        let message = correction(for: rep, spec: spec)
        if let message {
            onTempoStreak = 0
            guard repsSinceAdvice >= cooldownReps else { repsSinceAdvice += 1; return nil }
            repsSinceAdvice = 0
            return message
        }
        repsSinceAdvice += 1
        onTempoStreak += 1
        if onTempoStreak >= 3, repsSinceAdvice >= cooldownReps {
            onTempoStreak = 0
            repsSinceAdvice = 0
            return "dobrze, tak trzymaj"
        }
        return nil
    }

    private func correction(for rep: RepTempo, spec: TempoSpec) -> String? {
        if !rep.isFullRange { return "głębiej" }
        if spec.eccentric >= 2, rep.eccentric < spec.eccentric * 0.7 { return "wolniej w dół" }
        if spec.concentric >= 2, rep.concentric < spec.concentric * 0.6 { return "spokojniej w górę" }
        if spec.bottomPause >= 1, rep.bottomPause < spec.bottomPause * 0.5 { return "przytrzymaj na dole" }
        return nil
    }
}
