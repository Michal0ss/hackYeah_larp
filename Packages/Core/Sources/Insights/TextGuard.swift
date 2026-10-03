import Foundation
import Contracts

/// On-device check of model-written copy for the daily recommendation. The backend runs the same rules
/// (`backend/app/services/safety.py`); this is the second line of defence, so a text that slipped through or was
/// altered on the way is still never shown. Patterns are written against folded text (lowercase, no Polish
/// diacritics). Keep both lists in sync: the shared corpus `backend/scripts/text_safety_corpus.json` is checked
/// by the backend script and by `TextGuardTests`.
public enum TextGuard {
    static let forbidden: [(category: String, patterns: [String])] = [
        ("diagnosis", [
            "(?<!nie )(?<!nie jest )diagnoz",
            "\\bmasz\\s+(zapalenie|przepuklin|dyskopati|rwe|tendinopati|zerwani|naderwani|skrecen|zwichni|kontuzj|uraz)",
            "\\bto\\s+(jest\\s+)?(zapalenie|przepuklina|dyskopatia|tendinopatia|zerwanie|naderwanie|kontuzja|uraz)",
            "\\b(przetrenowani|wypalenie|depresj|zaburzeni|stan\\s+zapaln|cukrzyc|nadcisnieni|arytmi|niedoczynnos|nadczynnos)",
            "\\banemi",
            "\\b(uraz|kontuzj)",
            "\\bchorob",
            "\\bproblem\\w*\\s+z\\s+sercem",
            "\\btwoj\\w*\\s+\\w+\\s+(jest|sa)\\s+(uszkodzon|kontuzjowan|zniszczon)",
            "uszkodz",
        ]),
        ("medication", [
            "\\b(ibuprofen|paracetamol|ketonal|diclofenac|naproksen|aspiryn|sterydy|antybiotyk|opioid)",
            "\\bprzyjmij",
            "\\b(lek|leki|leku|lekiem|lekow|lekach|lekami)\\b",
            "\\bleczeni",
            "\\brecept",
            "\\bsuplement",
            "\\bwitamin",
            "\\bdawk",
            "\\b\\d+\\s*(mg|ml|tabletk|kapsulk)",
        ]),
        ("promise", [
            "\\b(za)?gwarantuj",
            "\\bna\\s+pewno\\b",
            "\\bz\\s+pewnoscia\\b",
            "\\b100\\s*%",
            "\\bbez\\s+ryzyka",
            "\\bzapobiegni",
            "\\bunikniesz\\b",
            "\\bwyleczy",
            "\\bpozbedziesz\\s+sie",
            "\\b(schudniesz|zbudujesz|poprawisz\\s+wynik)",
        ]),
        ("scare", [
            "\\bniebezpieczn", "\\bgrozi", "\\bzagrozen", "\\bpilnie\\b", "\\bnatychmiast", "\\balarm",
        ]),
        ("prohibition", [
            "\\bnie\\s+wolno", "\\bzabron", "\\bzakaz", "\\bmusisz\\b", "\\bkoniecznie\\b",
        ]),
        ("link", [
            "https?://", "www\\.", "\\b[a-z0-9-]+\\.(com|pl|org|net|io|eu)\\b", "\\S+@\\S+",
        ]),
        ("markup", [
            "[#*`_]{2,}", "^#", "\\*\\*", "^\\s*[-*\\x{2022}]\\s", "\\[[^\\]]*\\]\\([^)]*\\)",
        ]),
        ("meta", [
            "\\bjako\\s+(model|ai|asystent|sztuczna)", "\\b(system\\w*\\s+prompt|instrukcj\\w+\\s+systemow)",
        ]),
    ]

    static let contradictions: [Decision: [String]] = [
        .train: ["\\bodpusc", "\\brezygn", "\\bnie\\s+cwicz", "\\blzejsz", "\\bskroc"],
        .adapt: ["\\btrenuj\\s+wedlug\\s+planu", "\\bpelny\\s+trening", "\\bcwicz\\s+jak\\s+zwykle"],
        .rest: ["\\btrenuj\\s+wedlug\\s+planu", "\\bpelny\\s+trening", "\\bcwicz\\s+jak\\s+zwykle"],
    ]

    private static let compiled: [(category: String, regex: NSRegularExpression)] = forbidden.map { entry in
        (entry.category, try! NSRegularExpression(pattern: entry.patterns.joined(separator: "|"), options: [.anchorsMatchLines]))
    }
    private static let compiledContradictions: [Decision: NSRegularExpression] = contradictions.mapValues {
        try! NSRegularExpression(pattern: $0.joined(separator: "|"))
    }
    private static let emoji = try! NSRegularExpression(
        pattern: "[\\x{1F000}-\\x{1FAFF}\\x{2600}-\\x{27BF}\\x{2B00}-\\x{2BFF}\\x{FE0F}]")
    private static let number = try! NSRegularExpression(pattern: "\\d+(?:[.,]\\d+)?")

    /// Lowercase and strip Polish diacritics, so "ból" and "bol" match the same pattern.
    static func fold(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "ł", with: "l")
            .folding(options: .diacriticInsensitive, locale: nil)
    }

    static func numbers(in text: String) -> Set<String> {
        let range = NSRange(text.startIndex..., in: text)
        return Set(number.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).map { String(text[$0]).replacingOccurrences(of: ",", with: ".") }
        })
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// Problem codes for generated copy; empty means fine to show. Same codes as the backend.
    /// - Parameters:
    ///   - source: everything the model was given. The text may not contain numbers that are not in it.
    ///   - decision: checked for contradictions.
    public static func problems(in texts: [String], source: String? = nil, decision: Decision? = nil,
                                maxTotal: Int = 600) -> [String] {
        var problems: [String] = []
        let joined = texts.joined(separator: " ")
        if texts.isEmpty || texts.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            problems.append("empty")
        }
        if joined.count > maxTotal { problems.append("too_long") }
        let folded = fold(joined)
        for entry in compiled where matches(entry.regex, folded) {
            problems.append("unsafe_phrase:\(entry.category)")
        }
        if matches(emoji, joined) { problems.append("unsafe_phrase:emoji") }
        if let source, !numbers(in: joined).subtracting(numbers(in: source)).isEmpty {
            problems.append("invented_number")
        }
        if let decision, let regex = compiledContradictions[decision], matches(regex, folded) {
            problems.append("contradicts_decision")
        }
        return problems
    }

    /// Everything the model is given about a recommendation (the numbers it may repeat).
    public static func sourceText(for recommendation: DailyRecommendation) -> String {
        var parts = [recommendation.headline, recommendation.suggestedAction] + recommendation.factors.map(\.text)
        if let care = recommendation.careFlag { parts.append(care.reason) }
        return parts.joined(separator: " ")
    }

    /// Full check of a headline and explanation for a recommendation, including the care hint rule:
    /// when the engine raised a care flag, the text must point to a physiotherapist or a doctor.
    public static func problems(headline: String, explanation: String, for recommendation: DailyRecommendation) -> [String] {
        var found = problems(in: [headline, explanation], source: sourceText(for: recommendation),
                             decision: recommendation.decision)
        if recommendation.careFlag != nil {
            let folded = fold(explanation)
            if !folded.contains("fizjoterap") && !folded.contains("lekarz") { found.append("missing_care_hint") }
        }
        return found
    }
}
