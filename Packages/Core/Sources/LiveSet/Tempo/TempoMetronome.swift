import Foundation
import Contracts

/// The fixed clock of a set: when each beep sounds, counted from the moment the coach says "zaczynaj". It follows
/// only the plan's tempo (`TempoSpec`), never the person's movement, so the beeps stay evenly spaced like a
/// metronome and the person moves to them. One beep marks the start of the lowering phase, another the start of the
/// lifting phase; the pauses get no beep.
public struct TempoMetronome: Sendable {
    public struct Beat: Equatable, Sendable {
        public var phase: RepPhase
        /// Seconds after the start command.
        public var offset: Double
    }

    /// Time between the command and the first phase, so the person can get into position.
    public let leadIn: Double
    /// Length of one full repetition.
    public let cycleDuration: Double
    /// Beats within one repetition, offsets from its start, in order.
    private let cycle: [(phase: RepPhase, offset: Double)]

    /// `reversed`: the exercise begins with the lifting phase (a pull-up), so the cycle starts there.
    public init(spec: TempoSpec, reversed: Bool = false, leadIn: Double = 2) {
        self.leadIn = leadIn
        let steps: [(RepPhase, Double)] = reversed
            ? [(.concentric, spec.concentric), (.bottomPause, spec.bottomPause), (.eccentric, spec.eccentric), (.topPause, spec.topPause)]
            : [(.eccentric, spec.eccentric), (.bottomPause, spec.bottomPause), (.concentric, spec.concentric), (.topPause, spec.topPause)]
        var elapsed = 0.0
        var beats: [(RepPhase, Double)] = []
        for (phase, duration) in steps where duration > 0 {
            if phase == .eccentric || phase == .concentric { beats.append((phase, elapsed)) }
            elapsed += duration
        }
        self.cycleDuration = elapsed
        self.cycle = beats
    }

    /// The n-th beep (from 0). Nil when the spec has no duration at all.
    public func beat(at index: Int) -> Beat? {
        guard cycleDuration > 0, !cycle.isEmpty, index >= 0 else { return nil }
        let repetition = index / cycle.count
        let entry = cycle[index % cycle.count]
        return Beat(phase: entry.phase, offset: leadIn + Double(repetition) * cycleDuration + entry.offset)
    }
}
