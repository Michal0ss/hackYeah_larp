import Foundation

public enum Decision: String, Codable, Sendable, CaseIterable {
    case train   // Trenuj
    case adapt   // Zmodyfikuj
    case rest    // Odpuść

    public var title: String {
        switch self {
        case .train: return "Trenuj"
        case .adapt: return "Zmodyfikuj"
        case .rest: return "Odpuść"
        }
    }
}

public enum FactorSource: String, Codable, Sendable {
    case sleep, hrv, restingHeartRate, checkIn, technique
}

public struct RecommendationFactor: Codable, Equatable, Sendable, Identifiable {
    public var id: String { source.rawValue }
    public var source: FactorSource
    /// Short text, e.g. "Sen 5 h 40 min".
    public var text: String
    /// True when this factor pushes towards a lighter day.
    public var isNegative: Bool

    public init(source: FactorSource, text: String, isNegative: Bool) {
        self.source = source
        self.text = text
        self.isNegative = isNegative
    }
}

/// "Warto rozważyć konsultację" signal. A signal, never a diagnosis.
public struct CareFlag: Codable, Equatable, Sendable {
    public var reason: String

    public init(reason: String) {
        self.reason = reason
    }
}

public struct DailyRecommendation: Codable, Equatable, Sendable {
    public var date: Date
    /// Decided by the rule engine. The language model never changes it.
    public var decision: Decision
    public var headline: String
    public var factors: [RecommendationFactor]
    public var suggestedAction: String
    public var careFlag: CareFlag?
    public var isSimulated: Bool

    public init(date: Date, decision: Decision, headline: String, factors: [RecommendationFactor],
                suggestedAction: String, careFlag: CareFlag? = nil, isSimulated: Bool = false) {
        self.date = date
        self.decision = decision
        self.headline = headline
        self.factors = factors
        self.suggestedAction = suggestedAction
        self.careFlag = careFlag
        self.isSimulated = isSimulated
    }
}
