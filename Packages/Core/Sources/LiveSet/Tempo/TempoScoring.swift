import Foundation
import Contracts

/// Compares measured phase durations with the target tempo.
/// Tolerance and weights are engineering values for the demo, not sports-science norms.
public enum TempoScoring {
    /// Allowed deviation in seconds for a target duration.
    public static func tolerance(_ target: Double) -> Double { max(0.5, 0.2 * target) }

    static func phaseScore(actual: Double, target: Double) -> Double {
        let deviation = abs(actual - target)
        let tol = tolerance(target)
        guard deviation > tol else { return 100 }
        let span = max(0.5, target * 0.6)
        return max(0, 100 * (1 - (deviation - tol) / span))
    }

    public static func repScore(_ rep: RepTempo, spec: TempoSpec) -> Double {
        var parts: [(score: Double, weight: Double)] = [
            (phaseScore(actual: rep.eccentric, target: spec.eccentric), 0.4),
            (phaseScore(actual: rep.concentric, target: spec.concentric), 0.3),
        ]
        if spec.bottomPause > 0 {
            parts.append((phaseScore(actual: rep.bottomPause, target: spec.bottomPause), 0.3))
        }
        let total = parts.reduce(0) { $0 + $1.weight }
        return parts.reduce(0) { $0 + $1.score * $1.weight } / total
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "pl_PL"), value)
    }

    public static func evaluate(reps: [RepTempo], spec: TempoSpec) -> (score: Int, findings: [TechniqueFinding]) {
        guard !reps.isEmpty else { return (0, []) }
        let score = Int((reps.map { repScore($0, spec: spec) }.reduce(0, +) / Double(reps.count)).rounded())
        var findings: [TechniqueFinding] = []
        let total = reps.count

        func phase(id: String, name: String, target: Double, values: [Double], fastDetail: String, slowDetail: String) {
            guard target > 0 else { return }
            let avg = values.reduce(0, +) / Double(values.count)
            let tol = tolerance(target)
            let fast = values.filter { $0 < target - tol }.count
            let slow = values.filter { $0 > target + tol }.count
            let measured = "Średnio \(seconds(avg)) s przy celu \(seconds(target)) s."
            if avg < target - tol {
                findings.append(TechniqueFinding(id: "\(id)_fast", title: "\(name): za szybko", detail: "\(measured) \(fastDetail)",
                                                 severity: avg < target * 0.6 ? .major : .minor, repsAffected: fast, repsTotal: total))
            } else if avg > target + tol {
                findings.append(TechniqueFinding(id: "\(id)_slow", title: "\(name): wolniej niż cel", detail: "\(measured) \(slowDetail)",
                                                 severity: .minor, repsAffected: slow, repsTotal: total))
            } else {
                findings.append(TechniqueFinding(id: "\(id)_ok", title: "\(name): w tempie", detail: measured,
                                                 severity: .good, repsAffected: 0, repsTotal: total))
            }
        }

        phase(id: "tempo_ecc", name: "Opuszczanie", target: spec.eccentric, values: reps.map(\.eccentric),
              fastDetail: "Zwolnij i licz w głowie razem z trenerem.",
              slowDetail: "To nie błąd, tylko wolniej niż zaplanowano.")
        phase(id: "tempo_conc", name: "Wstawanie", target: spec.concentric, values: reps.map(\.concentric),
              fastDetail: "Wstawaj spokojniej, bez szarpnięcia.",
              slowDetail: "To nie błąd, tylko wolniej niż zaplanowano.")
        if spec.bottomPause > 0 {
            phase(id: "tempo_pause", name: "Pauza na dole", target: spec.bottomPause, values: reps.map(\.bottomPause),
                  fastDetail: "Przytrzymaj na dole, zanim zaczniesz wstawać.",
                  slowDetail: "Pauza dłuższa niż zaplanowano.")
        }

        let totals = reps.map(\.totalSeconds)
        let mean = totals.reduce(0, +) / Double(totals.count)
        if reps.count >= 3, mean > 0 {
            let variance = totals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(totals.count)
            if variance.squareRoot() / mean > 0.2 {
                findings.append(TechniqueFinding(id: "tempo_irregular", title: "Nierówne tempo",
                                                 detail: "Czas powtórzeń mocno się różni. Staraj się powtarzać ten sam rytm.",
                                                 severity: .minor, repsAffected: reps.count, repsTotal: total))
            }
        }
        return (score, findings)
    }
}
