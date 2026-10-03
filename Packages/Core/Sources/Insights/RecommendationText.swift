import Foundation
import Contracts

public enum RecommendationTextSource: String, Codable, Sendable {
    /// Written on the phone from the rule engine's own data. Always available.
    case engine
    /// Rewritten by the language model on the backend and checked on both sides.
    case ai
}

/// Wording of today's recommendation. The decision is never part of it: it comes from the rules and only the
/// words around it can come from the model.
public struct RecommendationText: Codable, Equatable, Sendable {
    public var headline: String
    public var explanation: String
    public var source: RecommendationTextSource
    /// Why the model text was not used, e.g. `ai_unavailable`, `ai_text_rejected`, `offline`. Empty for model text.
    public var warnings: [String]

    public init(headline: String, explanation: String, source: RecommendationTextSource, warnings: [String] = []) {
        self.headline = headline
        self.explanation = explanation
        self.source = source
        self.warnings = warnings
    }

    /// True when the UI should say "Wersja z szablonu" (the model text is not what you see).
    public var isTemplate: Bool { source == .engine }
}

/// The text of the recommendation, local first.
public protocol RecommendationTexting: Sendable {
    /// Immediate text built from the engine's own data. Show it first, so the card never waits for the network.
    func localText(for recommendation: DailyRecommendation) -> RecommendationText
    /// Tries the language model when allowed and falls back to `localText`. Never throws.
    func text(for recommendation: DailyRecommendation) async -> RecommendationText
}

/// Reaches the model through the backend (`POST /v1/texts/recommendation`). Implemented in the app target on top
/// of `FormaAPI`, so this module does not depend on the network layer.
public protocol RecommendationTextFetching: Sendable {
    func fetch(_ recommendation: DailyRecommendation) async throws -> RemoteRecommendationText
}

public struct RemoteRecommendationText: Equatable, Sendable {
    public var headline: String
    public var explanation: String
    /// True for model text, false for the backend's own template.
    public var fromModel: Bool
    public var warnings: [String]

    public init(headline: String, explanation: String, fromModel: Bool, warnings: [String] = []) {
        self.headline = headline
        self.explanation = explanation
        self.fromModel = fromModel
        self.warnings = warnings
    }
}

/// The text the phone writes itself. Short, factual, same tone as the rest of the app: a signal, never a diagnosis.
public enum EngineText {
    public static func make(for recommendation: DailyRecommendation) -> RecommendationText {
        var parts: [String] = []
        let reasons = recommendation.factors.filter(\.isNegative).prefix(3).map { lowercasedFirst($0.text) }
        if !reasons.isEmpty {
            parts.append("Powód: " + reasons.joined(separator: "; ").trimmingCharacters(in: CharacterSet(charactersIn: ".")) + ".")
        }
        let action = recommendation.suggestedAction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !action.isEmpty { parts.append(action) }
        if recommendation.careFlag != nil {
            parts.append("Jeśli to się powtarza, warto rozważyć konsultację z fizjoterapeutą lub lekarzem.")
        }
        return RecommendationText(headline: recommendation.headline, explanation: parts.joined(separator: " "),
                                  source: .engine)
    }

    /// "Sen 5 h 40 min" -> "sen 5 h 40 min", but "HRV 38 ms" stays as it is.
    static func lowercasedFirst(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        let second = trimmed.dropFirst().first
        if first.isUppercase, let second, second.isUppercase { return trimmed }
        return first.lowercased() + trimmed.dropFirst()
    }
}
