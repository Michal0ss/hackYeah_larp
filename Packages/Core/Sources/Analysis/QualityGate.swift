import Contracts
import Foundation
import LiveSet

/// Checks whether a recorded clip is good enough to score (PROJECT.md 6.2), for squat, push-up or
/// pull-up. Reuses `FramingAssessor` (visibility, size, side view) and `SquatSignal`/`PhaseTracker`
/// (depth signal, rep counting) from `LiveSet` instead of re-detecting any of this from scratch.
public enum QualityGate {
    public struct Thresholds {
        /// Share of frames a visibility/side-view check must pass to count as "good enough".
        public var minVisibleRatio: Double
        /// Minimum person height (frame fraction) while standing still between reps.
        public var minBodyHeight: Double
        public var maxPeople: Int
        public var minReps: Int
        public var minFps: Double

        public init(minVisibleRatio: Double = 0.85, minBodyHeight: Double = 0.5, maxPeople: Int = 1,
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

    public static func assess(frames: [PoseFrame], kind: MovementKind = .squat,
                              thresholds: Thresholds = Thresholds()) -> QualityReport {
        guard frames.count >= 2 else {
            let check = QualityCheck(id: "frames", label: "Nagranie odczytane", passed: false,
                                    hint: "Nie udało się odczytać nagrania, spróbuj ponownie")
            return QualityReport(passed: false, checks: [check], userHint: check.hint)
        }

        var tally: [String: (passed: Int, total: Int, hint: String?)] = [:]
        var overCrowdedFrames = 0
        var signal = SquatSignal(kind: kind)
        var tracker = PhaseTracker()
        var completedReps = 0

        for frame in frames {
            let depth = signal.depth(for: frame)
            // Size only means something while the person is close to the start: mid-rep they are
            // naturally lower/higher in the frame (FramingAssessor's own rule for the live set,
            // reused here).
            let nearStart = (depth ?? 1) < 0.1
            let framing = FramingAssessor.assess(frame, kind: kind, checkSize: nearStart,
                                                 minBodyHeight: thresholds.minBodyHeight)
            for check in framing.checks {
                var entry = tally[check.id] ?? (0, 0, nil)
                entry.total += 1
                if check.passed { entry.passed += 1 } else if entry.hint == nil { entry.hint = check.hint }
                tally[check.id] = entry
            }

            if frame.peopleDetected > thresholds.maxPeople { overCrowdedFrames += 1 }

            if let depth {
                for event in tracker.update(time: frame.time, depth: depth) {
                    if case .repCompleted = event { completedReps += 1 }
                }
            }
        }

        func ratioCheck(_ id: String, label: String) -> QualityCheck {
            let entry = tally[id] ?? (0, 0, nil)
            let ratio = entry.total > 0 ? Double(entry.passed) / Double(entry.total) : 0
            let passed = ratio >= thresholds.minVisibleRatio
            return QualityCheck(id: id, label: label, passed: passed, hint: passed ? nil : entry.hint)
        }

        // FramingAssessor doesn't check "size" or "side_view" for every kind (e.g. pull-up has
        // neither) — only score a check here if frames actually fed it.
        var checks = [ratioCheck("full_body", label: "Cała sylwetka w kadrze")]
        if (tally["size"]?.total ?? 0) > 0 { checks.append(ratioCheck("size", label: "Odpowiednia wielkość w kadrze")) }
        if (tally["side_view"]?.total ?? 0) > 0 { checks.append(ratioCheck("side_view", label: "Ujęcie z boku")) }

        let peopleOK = overCrowdedFrames <= frames.count / 10
        checks.append(QualityCheck(id: "single_person", label: "Jedna osoba w kadrze", passed: peopleOK,
            hint: peopleOK ? nil : "W kadrze wykryłem więcej niż jedną osobę, nagraj w pustym pomieszczeniu"))

        let repsOK = completedReps >= thresholds.minReps
        checks.append(QualityCheck(id: "rep_count", label: "Co najmniej \(thresholds.minReps) powtórzenia",
            passed: repsOK, hint: repsOK ? nil : "Zrób co najmniej \(thresholds.minReps) powtórzenia"))

        let fps = estimatedFps(frames)
        let fpsOK = fps >= thresholds.minFps
        checks.append(QualityCheck(id: "fps", label: "Płynność nagrania", passed: fpsOK,
            hint: fpsOK ? nil : "Nagranie ma za mało klatek na sekundę, spróbuj nagrać w lepszym świetle"))

        return QualityReport(passed: checks.allSatisfy(\.passed), checks: checks,
                            userHint: checks.first { !$0.passed }?.hint)
    }

    private static func estimatedFps(_ frames: [PoseFrame]) -> Double {
        let duration = frames.last!.time - frames.first!.time
        guard duration > 0 else { return 0 }
        return Double(frames.count - 1) / duration
    }
}
