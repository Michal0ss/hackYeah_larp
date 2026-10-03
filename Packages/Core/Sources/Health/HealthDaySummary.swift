import Foundation
import Contracts

/// What Apple Health knows about one day, for display. Unlike `RecoverySnapshot` (which the rule engine needs
/// complete) every number can be missing: an iPhone without a watch has sleep but no resting heart rate or HRV.
public struct HealthDaySummary: Equatable, Sendable, Identifiable {
    /// Start of the day the numbers belong to (a night belongs to the morning you woke up).
    public var date: Date
    public var sleepMinutes: Int?
    public var restingHeartRate: Int?
    public var hrvMs: Int?
    /// Personal reference from the earlier days (median); equals the day's own value while there is too little history.
    public var restingHeartRateBaseline: Int?
    public var hrvBaselineMs: Int?
    /// True for sample data. The UI must show the "Dane przykładowe" badge.
    public var isSimulated: Bool

    public var id: Date { date }

    public init(date: Date, sleepMinutes: Int? = nil, restingHeartRate: Int? = nil, hrvMs: Int? = nil,
                restingHeartRateBaseline: Int? = nil, hrvBaselineMs: Int? = nil, isSimulated: Bool = false) {
        self.date = date
        self.sleepMinutes = sleepMinutes
        self.restingHeartRate = restingHeartRate
        self.hrvMs = hrvMs
        self.restingHeartRateBaseline = restingHeartRateBaseline
        self.hrvBaselineMs = hrvBaselineMs
        self.isSimulated = isSimulated
    }

    public init(_ snapshot: RecoverySnapshot) {
        self.init(date: snapshot.date, sleepMinutes: snapshot.sleepMinutes, restingHeartRate: snapshot.restingHeartRate,
                  hrvMs: snapshot.hrvMs, restingHeartRateBaseline: snapshot.restingHeartRateBaseline,
                  hrvBaselineMs: snapshot.hrvBaselineMs, isSimulated: snapshot.isSimulated)
    }

    public var isEmpty: Bool { sleepMinutes == nil && restingHeartRate == nil && hrvMs == nil }

    /// The complete snapshot for the rule engine, or nil while any number is missing.
    public var snapshot: RecoverySnapshot? {
        guard let sleepMinutes, let restingHeartRate, let hrvMs, let restingHeartRateBaseline, let hrvBaselineMs else {
            return nil
        }
        return RecoverySnapshot(date: date, sleepMinutes: sleepMinutes, restingHeartRate: restingHeartRate, hrvMs: hrvMs,
                                restingHeartRateBaseline: restingHeartRateBaseline, hrvBaselineMs: hrvBaselineMs,
                                isSimulated: isSimulated)
    }

    /// Resting heart rate minus the baseline, e.g. +3.
    public var restingHeartRateDelta: Int? {
        guard let restingHeartRate, let restingHeartRateBaseline else { return nil }
        return restingHeartRate - restingHeartRateBaseline
    }

    /// HRV against the baseline in percent, e.g. -18.
    public var hrvDeltaPercent: Int? {
        guard let hrvMs, let hrvBaselineMs, hrvBaselineMs > 0 else { return nil }
        return Int((Double(hrvMs - hrvBaselineMs) / Double(hrvBaselineMs) * 100).rounded())
    }

    /// "6 h 25 min", or "7 h" on the hour.
    public var sleepText: String? {
        guard let sleepMinutes else { return nil }
        let h = sleepMinutes / 60, m = sleepMinutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }
}
