import Foundation

/// Rule engine thresholds. Mirrors `content/config/insights.json` (the bundled copy is `InsightThresholds.default`,
/// the same JSON can arrive later from `/v1/config`). Engineering values for the demo, not clinical ones.
public struct InsightThresholds: Codable, Equatable, Sendable {
    public struct Signals: Codable, Equatable, Sendable {
        /// Sleep strictly below this is a signal.
        public var sleepMinutesLow = 360
        /// HRV delta vs baseline strictly below this is a signal (e.g. -0.15 = 15% under).
        public var hrvBelowBaselineRatio = -0.15
        /// Resting heart rate strictly more than this above baseline is a signal.
        public var restingHeartRateAboveBaseline = 5
        /// Stress at or above this (1...5) is a signal.
        public var stressHigh = 4
        /// Energy at or below this (1...5) is a signal.
        public var energyLow = 2
        /// Technique score strictly below this is a signal.
        public var techniqueScoreLow = 60

        public init() {}

        private enum CodingKeys: String, CodingKey {
            case sleepMinutesLow, hrvBelowBaselineRatio, restingHeartRateAboveBaseline, stressHigh, energyLow,
                 techniqueScoreLow
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Signals()
            sleepMinutesLow = try c.decodeIfPresent(Int.self, forKey: .sleepMinutesLow) ?? d.sleepMinutesLow
            hrvBelowBaselineRatio = try c.decodeIfPresent(Double.self, forKey: .hrvBelowBaselineRatio) ?? d.hrvBelowBaselineRatio
            restingHeartRateAboveBaseline = try c.decodeIfPresent(Int.self, forKey: .restingHeartRateAboveBaseline)
                ?? d.restingHeartRateAboveBaseline
            stressHigh = try c.decodeIfPresent(Int.self, forKey: .stressHigh) ?? d.stressHigh
            energyLow = try c.decodeIfPresent(Int.self, forKey: .energyLow) ?? d.energyLow
            techniqueScoreLow = try c.decodeIfPresent(Int.self, forKey: .techniqueScoreLow) ?? d.techniqueScoreLow
        }
    }

    public struct Decision: Codable, Equatable, Sendable {
        /// Recovery signals needed for "Zmodyfikuj". A technique signal alone is enough as well.
        public var adaptFromSignals = 1
        /// Recovery signals (sleep, HRV, heart rate, stress, energy) needed for "Odpuść".
        /// Technique never counts here. 4 keeps the prototype example (sleep + HRV + stress) at "Zmodyfikuj".
        public var restFromSignals = 4

        public init() {}

        private enum CodingKeys: String, CodingKey { case adaptFromSignals, restFromSignals }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Decision()
            adaptFromSignals = try c.decodeIfPresent(Int.self, forKey: .adaptFromSignals) ?? d.adaptFromSignals
            restFromSignals = try c.decodeIfPresent(Int.self, forKey: .restFromSignals) ?? d.restFromSignals
        }
    }

    public struct Care: Codable, Equatable, Sendable {
        /// Same technique finding in at least this many analyses within `windowDays`.
        public var repeatedFindingCount = 3
        public var windowDays = 14
        /// Days in a row with worrying recovery and low wellbeing together.
        public var persistentDays = 3
        /// Mood at or below this (1...5) counts as low.
        public var lowMood = 2

        public init() {}

        private enum CodingKeys: String, CodingKey { case repeatedFindingCount, windowDays, persistentDays, lowMood }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Care()
            repeatedFindingCount = try c.decodeIfPresent(Int.self, forKey: .repeatedFindingCount) ?? d.repeatedFindingCount
            windowDays = try c.decodeIfPresent(Int.self, forKey: .windowDays) ?? d.windowDays
            persistentDays = try c.decodeIfPresent(Int.self, forKey: .persistentDays) ?? d.persistentDays
            lowMood = try c.decodeIfPresent(Int.self, forKey: .lowMood) ?? d.lowMood
        }
    }

    public var signals = Signals()
    public var decision = Decision()
    public var care = Care()

    public init() {}

    public static let `default` = InsightThresholds()

    private enum CodingKeys: String, CodingKey { case signals, decision, care }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        signals = try c.decodeIfPresent(Signals.self, forKey: .signals) ?? Signals()
        decision = try c.decodeIfPresent(Decision.self, forKey: .decision) ?? Decision()
        care = try c.decodeIfPresent(Care.self, forKey: .care) ?? Care()
    }

    /// Decodes the `insights` config section (extra keys such as `version` and `note` are ignored).
    public static func decode(from data: Data) throws -> InsightThresholds {
        try JSONDecoder().decode(InsightThresholds.self, from: data)
    }
}
