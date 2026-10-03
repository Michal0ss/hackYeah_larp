import Foundation

/// Does the user's question mention pain or an injury? Then the answer comes with the "Warto rozważyć konsultację"
/// card (PROJECT.md 5.8), whatever the model writes: the decision is made here by a fixed list, not by the model.
/// A signal to talk to a specialist, never a diagnosis.
public enum PainSignal {
    private static let words: Set<String> = ["bol", "boli", "bola", "bolu", "bole", "bolem", "boly"]
    private static let prefixes = ["bolesn", "bolac", "kontuzj", "uraz", "naciagn", "naderw", "zwichn", "skrec", "dretw",
                                   "strzyk", "kluj", "dyskomfort"]

    /// Diacritic- and case-insensitive: "Boli mnie kolano", "ból w plecach", "naciągnąłem mięsień".
    public static func mentions(_ text: String) -> Bool {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pl_PL"))
        return folded.split { !$0.isLetter }.map(String.init).contains { token in
            words.contains(token) || prefixes.contains { token.hasPrefix($0) }
        }
    }
}
