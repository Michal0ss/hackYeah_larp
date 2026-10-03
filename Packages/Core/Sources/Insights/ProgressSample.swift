import Foundation
import Contracts

/// Simulated history for the Progress and Care screens when the phone has no real history yet (demo mode).
/// Matches the clickable prototype: six squat analyses from 58 to 72, the torso finding in the last three
/// (68, 70, 72), and a mood line that dips together with recovery over the last two days.
/// Everything here is `isSimulated`; the screens must show the "Dane przykładowe" badge when they use it.
public enum ProgressSample {
    public static func techniqueResults(now: Date = Date(), calendar: Calendar = .current) -> [TechniqueResult] {
        let today = calendar.startOfDay(for: now)
        func day(_ ago: Int) -> Date { calendar.date(byAdding: .day, value: -ago, to: today) ?? today }
        func torso(_ affected: Int) -> TechniqueFinding {
            TechniqueFinding(id: "torso_lean_high", title: "Pochylenie tułowia",
                             detail: "Tułów pochyla się za bardzo w najniższym punkcie.",
                             severity: .major, repsAffected: affected, repsTotal: 5)
        }
        let depthShallow = TechniqueFinding(id: "depth_low", title: "Głębokość", detail: "Zejdź trochę niżej.",
                                            severity: .minor, repsAffected: 2, repsTotal: 5)
        // (days ago, score, finding)
        let rows: [(Int, Int, TechniqueFinding?)] = [
            (21, 58, depthShallow), (17, 61, depthShallow), (13, 65, nil),
            (8, 68, torso(4)), (4, 70, torso(3)), (0, 72, torso(3)),
        ]
        return rows.map { ago, score, finding in
            TechniqueResult(
                exerciseId: "squat", date: day(ago), score: score,
                componentScores: ["depth": 88, "torso": 58, "repeatability": 76, "tempo": 70],
                findings: finding.map { [$0] } ?? [], reps: [],
                substituteExerciseId: "goblet_squat", isSimulated: true)
        }
    }

    /// Mood on 14 days, newest first. Falls over the last two days like recovery in `SampleData.recovery`.
    public static func checkIns(now: Date = Date(), calendar: Calendar = .current) -> [CheckIn] {
        let today = calendar.startOfDay(for: now)
        let mood = [3, 3, 4, 4, 4, 5, 4, 4, 3, 4, 4, 4, 5, 4]
        let stress = [4, 4, 2, 2, 3, 2, 2, 3, 3, 2, 2, 2, 2, 2]
        return (0..<14).map { i in
            CheckIn(date: calendar.date(byAdding: .day, value: -i, to: today) ?? today,
                    mood: mood[i], stress: stress[i], energy: 3)
        }
    }
}
