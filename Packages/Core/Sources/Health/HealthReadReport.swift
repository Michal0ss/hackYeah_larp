import Foundation

/// What the last Apple Health read found, so "no data" can say why: nothing of the three types in Health, only
/// "in bed" time, or the read itself failed. Counts only, never the samples.
public struct HealthReadReport: Equatable, Sendable {
    /// How many days back the read looked.
    public var lookbackDays: Int
    /// Sleep samples in an "asleep" stage (core, deep, REM or unspecified).
    public var sleepSamples: Int
    /// Sleep samples that only say "in bed" or "awake". An iPhone without a watch records this; we do not count it
    /// as sleep.
    public var inBedSamples: Int
    public var restingHeartRateSamples: Int
    public var hrvSamples: Int
    /// Set when the read failed (for example the phone was locked), nil when it completed.
    public var errorDescription: String?

    public init(lookbackDays: Int, sleepSamples: Int = 0, inBedSamples: Int = 0, restingHeartRateSamples: Int = 0,
                hrvSamples: Int = 0, errorDescription: String? = nil) {
        self.lookbackDays = lookbackDays
        self.sleepSamples = sleepSamples
        self.inBedSamples = inBedSamples
        self.restingHeartRateSamples = restingHeartRateSamples
        self.hrvSamples = hrvSamples
        self.errorDescription = errorDescription
    }

    public init(samples: HealthSamples, lookbackDays: Int) {
        self.init(lookbackDays: lookbackDays, sleepSamples: samples.sleep.count, inBedSamples: samples.inBedCount,
                  restingHeartRateSamples: samples.restingHeartRate.count, hrvSamples: samples.hrv.count)
    }

    public var failed: Bool { errorDescription != nil }

    /// True when the read completed and found none of the three numbers.
    public var foundNothing: Bool { !failed && sleepSamples + restingHeartRateSamples + hrvSamples == 0 }

    /// One line for the screen, e.g. "Znaleziono (22 dni): sen 0, tętno spoczynkowe 0, HRV 0, w łóżku 14."
    public var summaryText: String {
        if let errorDescription { return "Odczyt nie powiódł się: \(errorDescription)" }
        var text = "Znaleziono (\(lookbackDays) dni): sen \(sleepSamples), tętno spoczynkowe \(restingHeartRateSamples), HRV \(hrvSamples)"
        if inBedSamples > 0 { text += ", tylko „w łóżku” \(inBedSamples)" }
        return text + "."
    }
}

/// The report of the latest read, shared between the Health service and the app. Lock-protected like
/// `HealthDataGate`.
public final class HealthReadLog: @unchecked Sendable {
    public static let shared = HealthReadLog()

    private let lock = NSLock()
    private var report: HealthReadReport?

    public init() {}

    public var last: HealthReadReport? {
        get { lock.lock(); defer { lock.unlock() }; return report }
        set { lock.lock(); report = newValue; lock.unlock() }
    }
}
