import Foundation
import Contracts

/// Thresholds of the phase tracker. `depth` is measured in torso lengths below the standing position.
/// These are engineering values for the demo, to be tuned on real recordings.
public struct PhaseTrackerConfig: Sendable, Equatable {
    /// Depth above which a repetition may start.
    public var startDepth = 0.08
    /// Depth below which a repetition is finished.
    public var returnDepth = 0.06
    /// Depth at the last moment the person is considered still at the top.
    public var restDepth = 0.02
    /// Peak depth needed for a full-range repetition.
    public var minRepDepth = 0.30
    /// Speed (torso lengths per second) above which the body counts as moving.
    public var velocityThreshold = 0.10
    /// Seconds the body must stay slow near the bottom before a pause is reported.
    public var bottomHold = 0.15
    /// Depth band below the peak that counts as "at the bottom" when measuring the pause.
    public var bottomBand = 0.02
    public var smoothingTau = 0.12
    public var velocityWindow = 0.35
    /// Seconds without movement after the last repetition before `idleTimeout` is reported.
    public var idleTimeout = 6.0

    public init() {}

    /// Overrides defaults with values from remote config (content/config/tempo.json, "phaseTracker"). Unknown or
    /// missing keys keep their defaults.
    public init(values: [String: Double]) {
        self.init()
        startDepth = values["startDepth"] ?? startDepth
        returnDepth = values["returnDepth"] ?? returnDepth
        restDepth = values["restDepth"] ?? restDepth
        minRepDepth = values["minRepDepth"] ?? minRepDepth
        velocityThreshold = values["velocityThreshold"] ?? velocityThreshold
        bottomHold = values["bottomHold"] ?? bottomHold
        bottomBand = values["bottomBand"] ?? bottomBand
        smoothingTau = values["smoothingTau"] ?? smoothingTau
        velocityWindow = values["velocityWindow"] ?? velocityWindow
        idleTimeout = values["idleTimeout"] ?? idleTimeout
    }
}

public enum TrackerEvent: Equatable, Sendable {
    /// Reported when the phase is detected (a few tenths after it really starts).
    case phaseStarted(RepPhase, detectedAt: Double)
    case repCompleted(RepTempo)
    case idleTimeout
}

/// Turns a stream of `depth` samples into repetition phases and their durations.
/// Pure logic, no camera: easy to test with synthetic signals.
public struct PhaseTracker {
    private struct Sample { var t: Double; var d: Double }

    public private(set) var phase: RepPhase?
    public private(set) var repCount = 0
    public private(set) var smoothedDepth = 0.0
    public private(set) var velocity = 0.0

    private let config: PhaseTrackerConfig
    private var window: [Sample] = []
    private var lastTime: Double?

    private var lastRestTime: Double?
    private var lastRepEnd: Double?
    private var idleReported = false

    private var repSamples: [Sample] = []
    private var eccStart = 0.0
    private var peakDepth = 0.0
    private var slowSince: Double?
    private var hasBottomPause = false
    private var topPauseBefore = 0.0
    private var concDetectedAt = 0.0

    public init(config: PhaseTrackerConfig = PhaseTrackerConfig()) {
        self.config = config
    }

    public mutating func reset() {
        self = PhaseTracker(config: config)
    }

    public mutating func update(time: Double, depth: Double) -> [TrackerEvent] {
        var events: [TrackerEvent] = []

        // Smoothing and velocity.
        if let last = lastTime {
            let dt = max(time - last, 0.001)
            smoothedDepth += (1 - exp(-dt / config.smoothingTau)) * (depth - smoothedDepth)
        } else {
            smoothedDepth = depth
        }
        lastTime = time
        window.append(Sample(t: time, d: smoothedDepth))
        window.removeAll { time - $0.t > config.velocityWindow * 1.5 }
        if let ref = window.first(where: { time - $0.t <= config.velocityWindow }), time - ref.t >= 0.15 {
            velocity = (smoothedDepth - ref.d) / (time - ref.t)
        }
        let d = smoothedDepth
        let v = velocity
        let vt = config.velocityThreshold

        if phase != nil { repSamples.append(Sample(t: time, d: d)) }

        switch phase {
        case nil:
            if d <= config.restDepth { lastRestTime = time }
            if v > vt && d > config.startDepth {
                beginEccentric(at: time)
                events.append(.phaseStarted(.eccentric, detectedAt: time))
            } else if repCount > 0, !idleReported, let end = lastRepEnd, time - end > config.idleTimeout {
                idleReported = true
                events.append(.idleTimeout)
            }

        case .eccentric:
            peakDepth = max(peakDepth, d)
            if v < -vt {
                // Reversal without a pause.
                hasBottomPause = false
                concDetectedAt = time
                phase = .concentric
                events.append(.phaseStarted(.concentric, detectedAt: time))
            } else if abs(v) < vt, d >= config.minRepDepth * 0.8 {
                let since = slowSince ?? time
                slowSince = since
                if time - since >= config.bottomHold {
                    hasBottomPause = true
                    phase = .bottomPause
                    events.append(.phaseStarted(.bottomPause, detectedAt: time))
                }
            } else {
                slowSince = nil
            }

        case .bottomPause:
            peakDepth = max(peakDepth, d)
            if v < -vt {
                concDetectedAt = time
                phase = .concentric
                events.append(.phaseStarted(.concentric, detectedAt: time))
            }

        case .concentric:
            if d <= config.returnDepth {
                events.append(.repCompleted(finishRep(at: time)))
                phase = nil
            } else if v > vt && d > config.startDepth {
                // Went down again before reaching the top: close this one and start the next.
                events.append(.repCompleted(finishRep(at: time)))
                beginEccentric(at: time)
                events.append(.phaseStarted(.eccentric, detectedAt: time))
            }

        case .topPause:
            break
        }
        return events
    }

    private mutating func beginEccentric(at time: Double) {
        let start = lastRestTime ?? max(time - 0.5, 0)
        eccStart = start
        topPauseBefore = lastRepEnd.map { max(0, start - $0) } ?? 0
        peakDepth = smoothedDepth
        slowSince = nil
        hasBottomPause = false
        repSamples = [Sample(t: time, d: smoothedDepth)]
        phase = .eccentric
    }

    private mutating func finishRep(at time: Double) -> RepTempo {
        // Bottom = samples within a small band of the peak.
        let near = repSamples.filter { $0.d >= peakDepth - config.bottomBand }
        let arrive = near.first?.t ?? time
        let leave = near.last?.t ?? time
        let ecc = max(0, arrive - eccStart)
        let pause = hasBottomPause ? max(0, leave - arrive) : 0
        let conc = max(0, time - (hasBottomPause ? leave : arrive))
        repCount += 1
        let rep = RepTempo(index: repCount, startedAt: eccStart, eccentric: ecc, bottomPause: pause,
                           concentric: conc, topPauseBefore: topPauseBefore, peakDepth: peakDepth,
                           isFullRange: peakDepth >= config.minRepDepth)
        lastRepEnd = time
        lastRestTime = time
        idleReported = false
        repSamples = []
        peakDepth = 0
        return rep
    }
}
