import Foundation

/// Daily recovery summary (not raw HealthKit samples).
public struct RecoverySnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: Date { date }
    public var date: Date
    public var sleepMinutes: Int
    public var restingHeartRate: Int
    public var hrvMs: Int
    /// Personal reference from the last days.
    public var restingHeartRateBaseline: Int
    public var hrvBaselineMs: Int
    public var isSimulated: Bool

    public init(date: Date, sleepMinutes: Int, restingHeartRate: Int, hrvMs: Int,
                restingHeartRateBaseline: Int, hrvBaselineMs: Int, isSimulated: Bool = false) {
        self.date = date
        self.sleepMinutes = sleepMinutes
        self.restingHeartRate = restingHeartRate
        self.hrvMs = hrvMs
        self.restingHeartRateBaseline = restingHeartRateBaseline
        self.hrvBaselineMs = hrvBaselineMs
        self.isSimulated = isSimulated
    }

    /// HRV relative to baseline, e.g. -0.18 for 18% below.
    public var hrvDeltaRatio: Double {
        guard hrvBaselineMs > 0 else { return 0 }
        return Double(hrvMs - hrvBaselineMs) / Double(hrvBaselineMs)
    }
}

public struct CheckIn: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    /// 1...5 each.
    public var mood: Int
    public var stress: Int
    public var energy: Int
    public var note: String?

    public init(id: UUID = UUID(), date: Date, mood: Int, stress: Int, energy: Int, note: String? = nil) {
        self.id = id
        self.date = date
        self.mood = mood
        self.stress = stress
        self.energy = energy
        self.note = note
    }
}
