import Contracts
import Foundation
import LiveSet

/// Checks whether a recorded clip is good enough to score (PROJECT.md 6.2), for squat, push-up or pull-up.
/// Reuses `FramingAssessor` (visibility, size, side view) from `LiveSet` for every frame of the part of the clip in
/// which the exercise is done, and `ClipRepDetector` to count the repetitions of the whole clip. Every failed check
/// carries the measured numbers (`QualityCheck.detail`), so a rejected clip can be explained.
public enum QualityGate {
    public struct Thresholds {
        /// Share of frames a visibility/side-view check must pass to count as "good enough".
        public var minVisibleRatio: Double
        /// Minimum person height (frame fraction) while standing still between reps.
        public var minBodyHeight: Double
        public var maxPeople: Int
        public var minReps: Int
        public var minFps: Double

        public init(minVisibleRatio: Double = 0.7, minBodyHeight: Double = 0.35, maxPeople: Int = 1,
                    minReps: Int = 3, minFps: Double = 24) {
            self.minVisibleRatio = minVisibleRatio
            self.minBodyHeight = minBodyHeight
            self.maxPeople = maxPeople
            self.minReps = minReps
            self.minFps = minFps
        }

        /// Values from `content/config/scoring.json` (section "quality"), falling back to the
        /// defaults above for anything missing.
        public static func from(_ numbers: [String: Double]) -> Thresholds {
            let d = Thresholds()
            return Thresholds(
                minVisibleRatio: numbers["minVisibleRatio"] ?? d.minVisibleRatio,
                minBodyHeight: numbers["minBodyHeight"] ?? d.minBodyHeight,
                maxPeople: numbers["maxPeople"].map(Int.init) ?? d.maxPeople,
                minReps: numbers["minReps"].map(Int.init) ?? d.minReps,
                minFps: numbers["minFps"] ?? d.minFps
            )
        }
    }

    /// The report, and what the app needs to decide whether to offer analysing the clip despite the failed checks.
    public struct Evaluation {
        public var report: QualityReport
        public var detection: ClipRepDetection
        /// True when there is something to analyse: at least one repetition and the body measured in most frames. Then
        /// failed checks are warnings the person may override ("Analizuj mimo to"); otherwise the clip must be redone.
        public var canAnalyzeAnyway: Bool
    }

    public static func assess(frames: [PoseFrame], kind: MovementKind = .squat,
                              thresholds: Thresholds = Thresholds(),
                              clip: ClipRepDetector.Config = ClipRepDetector.Config()) -> QualityReport {
        evaluate(frames: frames, kind: kind, thresholds: thresholds, clip: clip).report
    }

    public static func evaluate(frames: [PoseFrame], kind: MovementKind = .squat,
                                thresholds: Thresholds = Thresholds(),
                                clip: ClipRepDetector.Config = ClipRepDetector.Config()) -> Evaluation {
        let noDetection = ClipRepDetection(reps: [], signal: [], measuredFrames: 0, totalFrames: frames.count, amplitude: 0)
        guard frames.count >= 2 else {
            let check = QualityCheck(id: "frames", label: "Nagranie odczytane", passed: false,
                                    hint: "Nie udało się odczytać nagrania, spróbuj ponownie",
                                    detail: "Odczytano \(frames.count) klatek.")
            return Evaluation(report: QualityReport(passed: false, checks: [check], userHint: check.hint),
                              detection: noDetection, canAnalyzeAnyway: false)
        }

        // 1. Repetitions of the whole clip: the clip is known as a whole, so no live calibration is needed.
        let detection = ClipRepDetector.detect(frames: frames, kind: kind, config: clip)

        // 2. Framing, only where the exercise is done: walking to the phone and back says nothing about the framing.
        let window: ClosedRange<Double> = {
            guard let first = detection.reps.first, let last = detection.reps.last else {
                return -Double.infinity...Double.infinity
            }
            return (first.startTime - 0.5)...(last.endTime + 0.5)
        }()
        var tally: [String: (passed: Int, total: Int, hint: String?)] = [:]
        var overCrowdedFrames = 0
        var judged = 0
        for frame in frames where window.contains(frame.time) {
            judged += 1
            // Size only means something while the person is close to the start: mid-rep they are naturally
            // lower/higher in the frame (FramingAssessor's own rule for the live set, reused here).
            let framing = FramingAssessor.assess(frame, kind: kind, checkSize: isNearStart(frame.time, in: detection),
                                                 minBodyHeight: thresholds.minBodyHeight, minConfidence: clip.minConfidence)
            for check in framing.checks {
                var entry = tally[check.id] ?? (0, 0, nil)
                entry.total += 1
                if check.passed { entry.passed += 1 } else if entry.hint == nil { entry.hint = check.hint }
                tally[check.id] = entry
            }
            if frame.peopleDetected > thresholds.maxPeople { overCrowdedFrames += 1 }
        }

        func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

        func ratioCheck(_ id: String, label: String) -> QualityCheck {
            let entry = tally[id] ?? (0, 0, nil)
            let ratio = entry.total > 0 ? Double(entry.passed) / Double(entry.total) : 0
            let passed = ratio >= thresholds.minVisibleRatio
            return QualityCheck(id: id, label: label, passed: passed, hint: passed ? nil : entry.hint,
                                detail: "\(percent(ratio)) klatek w porządku (wymagane \(percent(thresholds.minVisibleRatio)))")
        }

        // FramingAssessor doesn't check "size" or "side_view" for every kind (e.g. pull-up has
        // neither) — only score a check here if frames actually fed it.
        var checks = [ratioCheck("full_body", label: "Cała sylwetka w kadrze")]
        if (tally["size"]?.total ?? 0) > 0 { checks.append(ratioCheck("size", label: "Odpowiednia wielkość w kadrze")) }
        if (tally["side_view"]?.total ?? 0) > 0 { checks.append(ratioCheck("side_view", label: "Ujęcie z boku")) }

        let crowdedShare = judged > 0 ? Double(overCrowdedFrames) / Double(judged) : 0
        let peopleOK = overCrowdedFrames <= judged / 10
        checks.append(QualityCheck(id: "single_person", label: "Jedna osoba w kadrze", passed: peopleOK,
            hint: peopleOK ? nil : "W kadrze wykryłem więcej niż jedną osobę, nagraj w pustym pomieszczeniu",
            detail: "\(percent(crowdedShare)) klatek z więcej niż jedną osobą (dopuszczalne 10%)"))

        let repCount = detection.reps.count
        let repsOK = repCount >= thresholds.minReps
        let repsHint: String? = repsOK ? nil
            : repCount == 0 ? (detection.amplitude < clip.minProminence(for: kind)
                ? "Nie widzę ruchu. Upewnij się, że cała sylwetka jest w kadrze, a ćwiczenie jest widoczne z boku"
                : "Nie rozpoznałem żadnego pełnego powtórzenia. Nagraj ćwiczenie całym zakresem ruchu")
            : "Zrób co najmniej \(thresholds.minReps) powtórzenia"
        checks.append(QualityCheck(id: "rep_count", label: "Co najmniej \(thresholds.minReps) powtórzenia",
            passed: repsOK, hint: repsHint,
            detail: "Wykryto \(repCount) (wymagane \(thresholds.minReps)). Zakres ruchu w nagraniu: \(String(format: "%.2f", detection.amplitude)) długości tułowia"))

        let fps = estimatedFps(frames)
        let fpsOK = fps >= thresholds.minFps
        checks.append(QualityCheck(id: "fps", label: "Płynność nagrania", passed: fpsOK,
            hint: fpsOK ? nil : "Nagranie ma za mało klatek na sekundę, spróbuj nagrać w lepszym świetle",
            detail: "\(Int(fps.rounded())) klatek/s (wymagane \(Int(thresholds.minFps)))"))

        // Nobody found at all: say that first, instead of "step back, I can't see your feet".
        let withPose = frames.filter { !$0.joints.isEmpty }.count
        if Double(withPose) < 0.1 * Double(frames.count) {
            checks.insert(QualityCheck(id: "person", label: "Sylwetka wykryta w nagraniu", passed: false,
                hint: "Nie wykryłem w nagraniu sylwetki. Cała osoba ma być w kadrze, w dobrym świetle, a telefon ma stać nieruchomo",
                detail: "Sylwetka w \(withPose) z \(frames.count) klatek"), at: 0)
        }

        let report = QualityReport(passed: checks.allSatisfy(\.passed), checks: checks,
                                   userHint: checks.first { !$0.passed }?.hint)
        let bodyMeasured = frames.isEmpty ? 0 : Double(detection.measuredFrames) / Double(frames.count)
        return Evaluation(report: report, detection: detection, canAnalyzeAnyway: repCount >= 1 && bodyMeasured >= 0.5)
    }

    /// True while the body is near its start position (the smoothed signal is in the lowest fifth of its range), or
    /// when nothing is known.
    private static func isNearStart(_ time: Double, in detection: ClipRepDetection) -> Bool {
        guard detection.amplitude > 0, !detection.signal.isEmpty else { return true }
        // The signal is sorted by time: the nearest sample by binary search.
        var lo = 0, hi = detection.signal.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if detection.signal[mid].time < time { lo = mid + 1 } else { hi = mid }
        }
        return detection.signal[lo].depth <= 0.2 * detection.amplitude
    }

    private static func estimatedFps(_ frames: [PoseFrame]) -> Double {
        let duration = frames.last!.time - frames.first!.time
        guard duration > 0 else { return 0 }
        return Double(frames.count - 1) / duration
    }
}
