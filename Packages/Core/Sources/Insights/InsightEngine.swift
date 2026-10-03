import Foundation
import Contracts

/// Everything the rule engine looks at. Pure data, so the engine is deterministic and testable.
public struct InsightInput: Sendable {
    /// Daily recovery summaries, newest first.
    public var snapshots: [RecoverySnapshot]
    /// Newest first.
    public var checkIns: [CheckIn]
    /// Newest first.
    public var techniqueResults: [TechniqueResult]
    /// Used only to name exercises in texts.
    public var catalog: [ExerciseItem]
    public var now: Date

    public init(snapshots: [RecoverySnapshot], checkIns: [CheckIn], techniqueResults: [TechniqueResult],
                catalog: [ExerciseItem] = [], now: Date = Date()) {
        self.snapshots = snapshots
        self.checkIns = checkIns
        self.techniqueResults = techniqueResults
        self.catalog = catalog
        self.now = now
    }
}

/// Rule engine for the daily recommendation (PROJECT.md 7.2-7.4). The decision is made here, never by the model.
/// All texts follow the tone rules (3.6): a signal, never a diagnosis.
public struct InsightEngine: Sendable {
    public var thresholds: InsightThresholds
    public var calendar: Calendar

    public init(thresholds: InsightThresholds = .default, calendar: Calendar = .current) {
        self.thresholds = thresholds
        self.calendar = calendar
    }

    public func recommend(_ input: InsightInput) -> DailyRecommendation {
        let day = calendar.startOfDay(for: input.now)
        let snapshot = input.snapshots.first { calendar.isDate($0.date, inSameDayAs: input.now) }
        let checkIn = input.checkIns.first { calendar.isDate($0.date, inSameDayAs: input.now) }
        let technique = input.techniqueResults.first

        var factors: [RecommendationFactor] = []
        var recoverySignals = 0

        if let s = snapshot {
            let sleepLow = s.sleepMinutes < thresholds.signals.sleepMinutesLow
            let hrvLow = s.hrvDeltaRatio < thresholds.signals.hrvBelowBaselineRatio
            let rhrDelta = s.restingHeartRate - s.restingHeartRateBaseline
            let rhrHigh = rhrDelta > thresholds.signals.restingHeartRateAboveBaseline
            factors.append(RecommendationFactor(source: .sleep, text: "Sen \(Self.duration(s.sleepMinutes))", isNegative: sleepLow))
            factors.append(RecommendationFactor(source: .hrv, text: Self.hrvText(s), isNegative: hrvLow))
            factors.append(RecommendationFactor(source: .restingHeartRate,
                                                text: "Tętno spoczynkowe \(s.restingHeartRate)" + (rhrDelta != 0 ? " (\(Self.signed(rhrDelta)))" : ""),
                                                isNegative: rhrHigh))
            recoverySignals += [sleepLow, hrvLow, rhrHigh].filter { $0 }.count
        }

        if let c = checkIn {
            let stressHigh = c.stress >= thresholds.signals.stressHigh
            let energyLow = c.energy <= thresholds.signals.energyLow
            var parts = ["Stres \(c.stress)/5"]
            if energyLow || !stressHigh { parts.append("energia \(c.energy)/5") }
            factors.append(RecommendationFactor(source: .checkIn, text: parts.joined(separator: ", "),
                                                isNegative: stressHigh || energyLow))
            recoverySignals += [stressHigh, energyLow].filter { $0 }.count
        }

        var techniqueSignal = false
        if let t = technique {
            let finding = Self.repeatedInReps(t)
            techniqueSignal = t.score < thresholds.signals.techniqueScoreLow || finding != nil
            let name = input.catalog.first { $0.id == t.exerciseId }?.name ?? "Technika"
            if let f = finding {
                factors.append(RecommendationFactor(
                    source: .technique,
                    text: "\(name): \(Self.lowercasedFirst(f.title)) w \(f.repsAffected) z \(f.repsTotal) powtórzeń",
                    isNegative: true))
            } else {
                factors.append(RecommendationFactor(source: .technique, text: "\(name): wynik \(t.score)/100",
                                                    isNegative: techniqueSignal))
            }
        }

        let decision: Decision
        if recoverySignals >= thresholds.decision.restFromSignals {
            decision = .rest
        } else if recoverySignals >= thresholds.decision.adaptFromSignals || techniqueSignal {
            decision = .adapt
        } else {
            decision = .train
        }

        let substituteName = technique?.substituteExerciseId.flatMap { id in input.catalog.first { $0.id == id }?.name }
        let (headline, action) = Self.texts(decision: decision, hasRecoveryData: snapshot != nil,
                                            recoverySignals: recoverySignals, substituteName: substituteName)

        let simulated = (snapshot?.isSimulated ?? false) || (technique?.isSimulated ?? false)
        return DailyRecommendation(date: day, decision: decision, headline: headline, factors: factors,
                                   suggestedAction: action, careFlag: careFlag(input), isSimulated: simulated)
    }

    // MARK: Care pathway (7.4)

    /// "Warto rozważyć konsultację": repeated technique finding, pain noted by the user, or worrying recovery
    /// together with low wellbeing over several days. Always a signal, never a diagnosis.
    public func careFlag(_ input: InsightInput) -> CareFlag? {
        let care = thresholds.care
        let windowStart = calendar.date(byAdding: .day, value: -care.windowDays, to: input.now) ?? input.now

        // 1. The same technique finding in several analyses.
        var counts: [String: (count: Int, title: String)] = [:]
        for r in input.techniqueResults where r.date >= windowStart && r.date <= input.now {
            for f in r.findings where f.severity != .good && f.repsAffected > 0 {
                counts[f.id, default: (0, f.title)].count += 1
            }
        }
        if let top = counts.values.filter({ $0.count >= care.repeatedFindingCount }).max(by: { $0.count < $1.count }) {
            return CareFlag(reason: "Ten sam sygnał („\(Self.lowercasedFirst(top.title))”) pojawił się w \(top.count) analizach z ostatnich \(care.windowDays) dni. To nie jest diagnoza. Fizjoterapeuta może ocenić ruch na żywo.")
        }

        // 2. Pain or discomfort written by the user in a recent check-in note.
        let noteStart = calendar.date(byAdding: .day, value: -2, to: input.now) ?? input.now
        if input.checkIns.contains(where: { $0.date >= noteStart && Self.mentionsPain($0.note) }) {
            return CareFlag(reason: "Zaznaczasz ból lub dyskomfort podczas ćwiczenia. To nie jest diagnoza, ale warto porozmawiać ze specjalistą.")
        }

        // 3. Worrying recovery and low wellbeing on several days in a row.
        if care.persistentDays > 0 {
            let allWorrying = (0..<care.persistentDays).allSatisfy { offset in
                guard let d = calendar.date(byAdding: .day, value: -offset, to: input.now),
                      let s = input.snapshots.first(where: { calendar.isDate($0.date, inSameDayAs: d) }),
                      let c = input.checkIns.first(where: { calendar.isDate($0.date, inSameDayAs: d) })
                else { return false }
                let flags = [s.sleepMinutes < thresholds.signals.sleepMinutesLow,
                             s.hrvDeltaRatio < thresholds.signals.hrvBelowBaselineRatio,
                             s.restingHeartRate - s.restingHeartRateBaseline > thresholds.signals.restingHeartRateAboveBaseline]
                    .filter { $0 }.count
                let lowWellbeing = c.mood <= care.lowMood || c.stress >= thresholds.signals.stressHigh
                return flags >= 2 && lowWellbeing
            }
            if allWorrying {
                return CareFlag(reason: "Od \(care.persistentDays) dni słabsza regeneracja idzie w parze z niższym samopoczuciem. To sygnał, nie diagnoza. Warto rozważyć rozmowę ze specjalistą.")
            }
        }
        return nil
    }

    // MARK: Helpers

    /// The finding that hit more than half of the reps, if any (worst first).
    static func repeatedInReps(_ r: TechniqueResult) -> TechniqueFinding? {
        r.findings
            .filter { $0.severity != .good && $0.repsTotal > 0 && $0.repsAffected * 2 > $0.repsTotal }
            .max { $0.repsAffected < $1.repsAffected }
    }

    static func texts(decision: Decision, hasRecoveryData: Bool, recoverySignals: Int,
                      substituteName: String?) -> (headline: String, action: String) {
        switch decision {
        case .train:
            if hasRecoveryData {
                return ("Trenuj według planu", "Regeneracja i samopoczucie bez niepokojących sygnałów. Zrób dzisiejszą sesję tak, jak jest w planie.")
            }
            return ("Trenuj według planu", "Nie mam danych o regeneracji, więc nie zmieniam sesji. Krótki check-in pozwoli ją doprecyzować.")
        case .adapt:
            var action = "Zrób o jedną serię mniej w każdym ćwiczeniu i obniż intensywność (RPE 6–7)."
            if let sub = substituteName { action += " Przy przysiadzie sięgnij po: \(Self.lowercasedFirst(sub))." }
            return (recoverySignals > 0 ? "Dziś lżejszy trening" : "Dziś trening z uwagą na technikę", action)
        case .rest:
            return ("Dziś regeneracja", "Odpuść mocny trening. Wybierz odpoczynek albo lekką aktywność, np. spacer lub kilka minut mobilności.")
        }
    }

    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    static func hrvText(_ s: RecoverySnapshot) -> String {
        let pct = Int((abs(s.hrvDeltaRatio) * 100).rounded())
        if pct < 2 { return "HRV \(s.hrvMs) ms, jak zwykle" }
        return s.hrvDeltaRatio < 0
            ? "HRV \(s.hrvMs) ms, \(pct)% poniżej twojej średniej"
            : "HRV \(s.hrvMs) ms, \(pct)% powyżej twojej średniej"
    }

    static func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : "\(n)" }

    static func lowercasedFirst(_ s: String) -> String {
        guard let f = s.first else { return s }
        return f.lowercased() + s.dropFirst()
    }

    private static let painWords: Set<String> = ["bol", "bolu", "bolem", "boli", "bola", "bole", "bolesny", "bolesne", "bolesna"]
    private static let painPrefixes = ["bolesn", "kontuzj", "uraz", "dyskomfort", "ciagn", "kluj", "drewn"]

    /// True when the note mentions pain or discomfort. Diacritic- and case-insensitive.
    static func mentionsPain(_ note: String?) -> Bool {
        guard let note, !note.isEmpty else { return false }
        let folded = note.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
        let tokens = folded.split { !$0.isLetter }.map(String.init)
        return tokens.contains { t in painWords.contains(t) || painPrefixes.contains { t.hasPrefix($0) } }
    }
}
