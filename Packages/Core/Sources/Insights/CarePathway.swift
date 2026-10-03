import Foundation
import Contracts

/// Why the "Warto rozważyć konsultację" card appears (PROJECT.md 7.4).
public enum CareSignalKind: Equatable, Sendable {
    /// The same technique finding in several analyses.
    case repeatedFinding(id: String, title: String)
    /// The user wrote about pain or discomfort in a check-in note.
    case painNote
    /// Worrying recovery together with low wellbeing over several days in a row.
    case persistentRecovery
}

/// One line of the "Skąd ten sygnał" list on the care screen.
public struct CareOccurrence: Equatable, Sendable, Identifiable {
    public var id: Date { date }
    public var date: Date
    public var text: String
    /// Technique score of that analysis, when the signal comes from analyses.
    public var score: Int?

    public init(date: Date, text: String, score: Int? = nil) {
        self.date = date
        self.text = text
        self.score = score
    }
}

/// Everything the care card needs. `flag.reason` is the short text carried by `DailyRecommendation.careFlag`.
public struct CareAssessment: Equatable, Sendable {
    public var kind: CareSignalKind
    public var flag: CareFlag
    /// Oldest first.
    public var evidence: [CareOccurrence]
    /// "Co możesz zrobić", in order.
    public var steps: [String]

    public init(kind: CareSignalKind, flag: CareFlag, evidence: [CareOccurrence], steps: [String]) {
        self.kind = kind
        self.flag = flag
        self.evidence = evidence
        self.steps = steps
    }
}

/// Decides when to suggest talking to a specialist. Always a signal, never a diagnosis, never a cause.
/// Pure and deterministic. Priority when several signals hold: pain written by the user, then a repeated
/// technique finding, then persistent recovery and wellbeing.
public struct CarePathway: Sendable {
    /// Shown next to every care card (PROJECT.md 7.4).
    public static let disclaimer = "W razie silnego bólu, urazu lub niepokojących objawów skontaktuj się z lekarzem. To nie jest porada medyczna."

    public var thresholds: InsightThresholds
    public var calendar: Calendar

    public init(thresholds: InsightThresholds = .default, calendar: Calendar = .current) {
        self.thresholds = thresholds
        self.calendar = calendar
    }

    public func assess(snapshots: [RecoverySnapshot], checkIns: [CheckIn], techniqueResults: [TechniqueResult],
                       now: Date = Date()) -> CareAssessment? {
        painAssessment(checkIns: checkIns, now: now)
            ?? repeatedFindingAssessment(techniqueResults: techniqueResults, now: now)
            ?? persistentAssessment(snapshots: snapshots, checkIns: checkIns, now: now)
    }

    // MARK: Signals

    private func painAssessment(checkIns: [CheckIn], now: Date) -> CareAssessment? {
        let start = calendar.date(byAdding: .day, value: -2, to: now) ?? now
        let notes = checkIns.filter { $0.date >= start && $0.date <= now && Self.mentionsPain($0.note) }
        guard !notes.isEmpty else { return nil }
        return CareAssessment(
            kind: .painNote,
            flag: CareFlag(reason: "Zaznaczasz ból lub dyskomfort podczas ćwiczenia. To nie jest diagnoza, ale warto porozmawiać ze specjalistą."),
            evidence: notes.sorted { $0.date < $1.date }
                .map { CareOccurrence(date: $0.date, text: "Twoja notatka z check-inu: „\($0.note ?? "")”") },
            steps: [
                "Zrób przerwę w ćwiczeniach, które wywołują ból lub dyskomfort.",
                "Porozmawiaj ze specjalistą, np. fizjoterapeutą, i opisz, kiedy to się pojawia.",
                "Wróć do planu, gdy dolegliwość minie albo specjalista wyrazi na to zgodę.",
            ])
    }

    private func repeatedFindingAssessment(techniqueResults: [TechniqueResult], now: Date) -> CareAssessment? {
        let care = thresholds.care
        let start = calendar.date(byAdding: .day, value: -care.windowDays, to: now) ?? now
        let inWindow = techniqueResults.filter { $0.date >= start && $0.date <= now }

        var counts: [String: Int] = [:]
        var titles: [String: String] = [:]
        for r in inWindow {
            for f in r.findings where f.severity != .good && f.repsAffected > 0 {
                counts[f.id, default: 0] += 1
                titles[f.id] = f.title
            }
        }
        // Most frequent first; ties broken by id so the result is deterministic.
        guard let top = counts.filter({ $0.value >= care.repeatedFindingCount })
            .sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).first,
              let title = titles[top.key] else { return nil }

        let evidence = inWindow.sorted { $0.date < $1.date }.compactMap { r -> CareOccurrence? in
            guard let f = r.findings.first(where: { $0.id == top.key && $0.severity != .good && $0.repsAffected > 0 })
            else { return nil }
            return CareOccurrence(date: r.date,
                                  text: "\(InsightEngine.lowercasedFirst(f.title)) w \(f.repsAffected) z \(f.repsTotal) powtórzeń",
                                  score: r.score)
        }
        return CareAssessment(
            kind: .repeatedFinding(id: top.key, title: title),
            flag: CareFlag(reason: "Ten sam sygnał („\(InsightEngine.lowercasedFirst(title))”) pojawił się w \(top.value) analizach z ostatnich \(care.windowDays) dni. To nie jest diagnoza. Fizjoterapeuta może ocenić ruch na żywo."),
            evidence: evidence,
            steps: [
                "Poproś fizjoterapeutę o ocenę ruchu na żywo i pokaż mu wynik analizy.",
                "Do tego czasu zostań przy lżejszych seriach i zamienniku ćwiczenia z planu.",
                "Nagraj ćwiczenie ponownie za tydzień. Porównamy wyniki.",
            ])
    }

    private func persistentAssessment(snapshots: [RecoverySnapshot], checkIns: [CheckIn], now: Date) -> CareAssessment? {
        let care = thresholds.care
        guard care.persistentDays > 0 else { return nil }
        var days: [Date] = []
        for offset in 0..<care.persistentDays {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now),
                  let s = snapshots.first(where: { calendar.isDate($0.date, inSameDayAs: day) }),
                  let c = checkIns.first(where: { calendar.isDate($0.date, inSameDayAs: day) }) else { return nil }
            let flags = [s.sleepMinutes < thresholds.signals.sleepMinutesLow,
                         s.hrvDeltaRatio < thresholds.signals.hrvBelowBaselineRatio,
                         s.restingHeartRate - s.restingHeartRateBaseline > thresholds.signals.restingHeartRateAboveBaseline]
                .filter { $0 }.count
            let lowWellbeing = c.mood <= care.lowMood || c.stress >= thresholds.signals.stressHigh
            guard flags >= 2, lowWellbeing else { return nil }
            days.append(calendar.startOfDay(for: day))
        }
        return CareAssessment(
            kind: .persistentRecovery,
            flag: CareFlag(reason: "Od \(care.persistentDays) dni słabsza regeneracja idzie w parze z niższym samopoczuciem. To sygnał, nie diagnoza. Warto rozważyć rozmowę ze specjalistą."),
            evidence: days.sorted().map { CareOccurrence(date: $0, text: "słabsza regeneracja i niższe samopoczucie") },
            steps: [
                "Daj sobie kilka lżejszych dni i zadbaj o sen.",
                "Jeśli to się utrzymuje, porozmawiaj z lekarzem rodzinnym albo innym specjalistą.",
                "Rób check-in codziennie, żebyśmy widzieli, czy robi się lepiej.",
            ])
    }

    // MARK: Pain words

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
