import Contracts
import Foundation
import LiveSet

/// One repetition found in a recorded clip.
public struct ClipRep: Equatable, Sendable, Identifiable {
    public var id: Int { index }
    /// 1-based.
    public var index: Int
    /// The standing / top / hang position the repetition started from, the working end (the lowest point of a squat
    /// and a push-up, the highest of a pull-up) and the position it returned to. Seconds from the start of the clip.
    public var startTime: Double
    public var bottomTime: Double
    public var endTime: Double
    /// The frames at those moments (the start and the bottom are the most extreme joint angles around them).
    public var startFrame: PoseFrame
    public var bottomFrame: PoseFrame
    /// Range of the movement in torso lengths.
    public var depth: Double
    /// Seconds from the start to the working end, and from there back.
    public var outSeconds: Double
    public var backSeconds: Double
}

/// What the detector found in a whole clip.
public struct ClipRepDetection: Sendable {
    public var reps: [ClipRep]
    /// The smoothed depth signal (torso lengths, grows towards the working end of the movement), for charts/debugging.
    public var signal: [(time: Double, depth: Double)]
    /// Frames in which the body could be measured, of all frames.
    public var measuredFrames: Int
    public var totalFrames: Int
    /// Range between the typical top and the typical working end, in torso lengths. Near zero = the person did not move.
    public var amplitude: Double
}

/// Finds repetitions in a recorded clip.
///
/// The live coach follows a set as it happens: it must calibrate on a second of stillness and reacts with a delay.
/// A recorded clip is known as a whole, so this looks at all of it at once: it needs no calibration, takes the start
/// position from the clip itself, and counts a repetition wherever the smoothed height of the hips (squat) or the
/// shoulders (push-up, pull-up) makes a clear, wide enough peak towards the working end of the movement.
public enum ClipRepDetector {
    public struct Config: Sendable, Equatable {
        /// Lowest joint confidence that counts as seen. Lower than live: a clip is judged as a whole.
        public var minConfidence = 0.15
        /// Seconds of the smoothing window (a median of 5 samples first, then a moving average over this time).
        public var smoothSeconds = 0.25
        /// A peak must rise at least this far (torso lengths) above the valley on its weaker side. The shoulders of a
        /// push-up move far less than the hips of a squat, so every exercise has its own limit.
        public var minProminenceSquat = 0.12
        public var minProminencePushup = 0.06
        public var minProminencePullup = 0.10
        /// A dip moves the shoulders about as far as a squat moves the hips (0.65-0.85 torso lengths in recordings).
        public var minProminenceDip = 0.10
        /// ... and at least this share of the typical prominence of the clip's peaks (drops jitter next to real reps).
        public var relativeProminence = 0.5
        /// A peak must be at least this wide (seconds) at half of its prominence: a tracking glitch is not a repetition.
        public var minWidthSeconds = 0.3
        /// Share of a repetition's range that counts as "left the start position" when timing it.
        public var edgeShare = 0.1
        /// The joint that defines the exercise (knee of a squat, elbow of a push-up and a pull-up) must bend by at least
        /// this many degrees between the start and the working end. Moving the whole body (walking up to the phone,
        /// bending to pick something up) shifts the hips like a squat does, but does not bend the knee.
        public var minAngleChange = 20.0

        public init() {}

        public func minProminence(for kind: MovementKind) -> Double {
            switch kind {
            case .squat: return minProminenceSquat
            case .pushup: return minProminencePushup
            case .pullup: return minProminencePullup
            case .dip: return minProminenceDip
            }
        }

        /// Values from `content/config/scoring.json` (section "clip"). Missing keys keep their defaults.
        public init(values: [String: Double]) {
            self.init()
            minConfidence = values["minConfidence"] ?? minConfidence
            smoothSeconds = values["smoothSeconds"] ?? smoothSeconds
            minProminenceSquat = values["minProminenceSquat"] ?? minProminenceSquat
            minProminencePushup = values["minProminencePushup"] ?? minProminencePushup
            minProminencePullup = values["minProminencePullup"] ?? minProminencePullup
            minProminenceDip = values["minProminenceDip"] ?? minProminenceDip
            relativeProminence = values["relativeProminence"] ?? relativeProminence
            minWidthSeconds = values["minWidthSeconds"] ?? minWidthSeconds
            edgeShare = values["edgeShare"] ?? edgeShare
            minAngleChange = values["minAngleChange"] ?? minAngleChange
        }
    }

    private struct Sample {
        var time: Double
        var depth: Double
        var frameIndex: Int
    }

    public static func detect(frames: [PoseFrame], kind: MovementKind, config: Config = Config()) -> ClipRepDetection {
        // 1. The raw signal: height of the point that follows the movement, in torso lengths.
        var raw: [(index: Int, y: Double, torso: Double)] = []
        for (index, frame) in frames.enumerated() {
            if let m = SquatSignal.measure(frame, kind: kind, minConfidence: config.minConfidence) {
                raw.append((index, m.hipY, m.torso))
            }
        }
        let empty = ClipRepDetection(reps: [], signal: [], measuredFrames: raw.count, totalFrames: frames.count, amplitude: 0)
        guard raw.count >= 8 else { return empty }

        let torso = median(raw.map(\.torso))
        // Positive towards the working end: down for a squat and a push-up, up for a pull-up.
        let sign: Double = kind == .pullup ? -1 : 1
        var depths = raw.map { sign * $0.y / torso }
        depths = medianFilter(depths, radius: 2)
        let times = raw.map { frames[$0.index].time }
        depths = movingAverage(depths, times: times, window: config.smoothSeconds)
        let samples = raw.indices.map { Sample(time: times[$0], depth: depths[$0], frameIndex: raw[$0].index) }

        // 2. The start position and the working end of the clip, from percentiles (robust against a stray jump).
        let sorted = depths.sorted()
        let low = percentile(sorted, 0.1)
        let high = percentile(sorted, 0.95)
        let amplitude = high - low
        let signal = samples.map { (time: $0.time, depth: $0.depth - low) }
        let minProminence = config.minProminence(for: kind)
        guard amplitude >= minProminence else {
            return ClipRepDetection(reps: [], signal: signal, measuredFrames: raw.count, totalFrames: frames.count, amplitude: amplitude)
        }

        // 3. Peaks with enough prominence and width.
        var peaks = prominentPeaks(samples, minProminence: minProminence, minWidth: config.minWidthSeconds)
        if peaks.count > 2 {
            let typical = median(peaks.map(\.prominence))
            peaks = peaks.filter { $0.prominence >= typical * config.relativeProminence }
        }

        // 4. For every peak: the valleys either side give the start and the end of the repetition.
        var reps: [ClipRep] = []
        for (n, peak) in peaks.enumerated() {
            let leftBound = n > 0 ? peaks[n - 1].index : 0
            let rightBound = n + 1 < peaks.count ? peaks[n + 1].index : samples.count - 1
            let leftValley = (leftBound...peak.index).min { samples[$0].depth < samples[$1].depth } ?? leftBound
            let rightValley = (peak.index...rightBound).min { samples[$0].depth < samples[$1].depth } ?? rightBound

            let top = samples[peak.index].depth
            let leftRange = top - samples[leftValley].depth
            let rightRange = top - samples[rightValley].depth
            // Leaves the start position: the last time at the valley level + edgeShare of the range, before the peak.
            let leftLevel = samples[leftValley].depth + config.edgeShare * leftRange
            let rightLevel = samples[rightValley].depth + config.edgeShare * rightRange
            var startIdx = peak.index
            while startIdx > leftValley, samples[startIdx].depth > leftLevel { startIdx -= 1 }
            var endIdx = peak.index
            while endIdx < rightValley, samples[endIdx].depth > rightLevel { endIdx += 1 }

            let startTime = samples[startIdx].time, bottomTime = samples[peak.index].time, endTime = samples[endIdx].time
            let bottom = extremeFrame(in: frames, around: bottomTime, radius: 0.2, kind: kind, wantMin: true)
                ?? frames[samples[peak.index].frameIndex]
            let start = extremeFrame(in: frames, around: samples[leftValley].time, radius: 0.25, kind: kind, wantMin: false)
                ?? frames[samples[leftValley].frameIndex]
            // The arms must have been extended at the start (a dip begins from a lockout): someone still climbing onto
            // the bars bends and straightens the arms without doing a repetition.
            if let minStart = kind.minStartElbowForClip,
               let startAngle = kind.primaryAngle(in: start, minConfidence: config.minConfidence), startAngle < minStart {
                continue
            }
            // The exercise's own joint must bend. When it cannot be measured the repetition is kept.
            if let a = kind.primaryAngle(in: start, minConfidence: config.minConfidence),
               let b = kind.primaryAngle(in: bottom, minConfidence: config.minConfidence),
               abs(a - b) < config.minAngleChange {
                continue
            }
            reps.append(ClipRep(index: reps.count + 1, startTime: startTime, bottomTime: bottomTime, endTime: endTime,
                                startFrame: start, bottomFrame: bottom, depth: peak.prominence,
                                outSeconds: max(0, bottomTime - startTime), backSeconds: max(0, endTime - bottomTime)))
        }
        return ClipRepDetection(reps: reps, signal: signal, measuredFrames: raw.count, totalFrames: frames.count, amplitude: amplitude)
    }

    // MARK: - Peaks

    private struct Peak { var index: Int; var prominence: Double }

    private static func prominentPeaks(_ samples: [Sample], minProminence: Double, minWidth: Double) -> [Peak] {
        let d = samples.map(\.depth)
        var peaks: [Peak] = []
        var i = 1
        while i < d.count - 1 {
            // A plateau counts as one peak, at its middle.
            var j = i
            while j + 1 < d.count, d[j + 1] == d[i] { j += 1 }
            let leftHigher = d[i - 1] < d[i]
            let rightLower = j + 1 < d.count ? d[j + 1] < d[i] : false
            if leftHigher, rightLower {
                let mid = (i + j) / 2
                if let peak = prominence(of: mid, in: d, minProminence: minProminence),
                   width(of: peak, at: mid, in: samples) >= minWidth {
                    peaks.append(peak)
                }
            }
            i = j + 1
        }
        return peaks
    }

    /// The topographic prominence: how far the peak rises above the higher of the two valleys that separate it from
    /// the next higher ground on each side (or the edge of the clip).
    private static func prominence(of p: Int, in d: [Double], minProminence: Double) -> Peak? {
        var leftMin = d[p]
        var k = p - 1
        while k >= 0, d[k] <= d[p] { leftMin = min(leftMin, d[k]); k -= 1 }
        var rightMin = d[p]
        k = p + 1
        while k < d.count, d[k] <= d[p] { rightMin = min(rightMin, d[k]); k += 1 }
        let prominence = d[p] - max(leftMin, rightMin)
        return prominence >= minProminence ? Peak(index: p, prominence: prominence) : nil
    }

    /// Seconds the signal stays above half of the peak's prominence around it.
    private static func width(of peak: Peak, at p: Int, in samples: [Sample]) -> Double {
        let level = samples[p].depth - peak.prominence / 2
        var l = p, r = p
        while l > 0, samples[l - 1].depth >= level { l -= 1 }
        while r < samples.count - 1, samples[r + 1].depth >= level { r += 1 }
        return samples[r].time - samples[l].time
    }

    // MARK: - Frames at the extremes

    private static func extremeFrame(in frames: [PoseFrame], around time: Double, radius: Double,
                                     kind: MovementKind, wantMin: Bool) -> PoseFrame? {
        kind.representativeFrame(in: frames, around: time, radius: radius, wantMin: wantMin)
    }

    // MARK: - Filters

    static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down)), upper = Int(position.rounded(.up))
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }

    private static func medianFilter(_ values: [Double], radius: Int) -> [Double] {
        values.indices.map { i in
            median(Array(values[max(0, i - radius)...min(values.count - 1, i + radius)]))
        }
    }

    /// Centered moving average over `window` seconds (handles uneven spacing of the samples).
    private static func movingAverage(_ values: [Double], times: [Double], window: Double) -> [Double] {
        guard window > 0 else { return values }
        var result: [Double] = []
        var lo = 0, hi = 0
        var sum = 0.0
        for i in values.indices {
            while hi < values.count, times[hi] <= times[i] + window / 2 { sum += values[hi]; hi += 1 }
            while lo < hi, times[lo] < times[i] - window / 2 { sum -= values[lo]; lo += 1 }
            result.append(hi > lo ? sum / Double(hi - lo) : values[i])
        }
        return result
    }
}
