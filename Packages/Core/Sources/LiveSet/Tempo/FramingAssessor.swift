import Foundation
import Contracts

public struct FramingReport: Equatable, Sendable {
    public var ready: Bool
    public var checks: [QualityCheck]
    /// The one hint to show, or nil when the framing is good.
    public var hint: String?

    public init(ready: Bool, checks: [QualityCheck], hint: String?) {
        self.ready = ready
        self.checks = checks
        self.hint = hint
    }
}

/// Live check that the person is framed well enough (side view, whole body, big enough).
/// Thresholds are engineering values for the demo.
public enum FramingAssessor {
    public static var minBodyHeight = 0.45
    public static var maxBodyHeight = 0.95
    /// Shoulder separation / torso length above which the person is probably facing the camera.
    public static var maxShoulderRatio = 0.5

    /// `checkSize` should be false while the person is moving through the exercise:
    /// a squatting person is naturally lower in the frame than a standing one.
    public static func assess(_ frame: PoseFrame?, kind: MovementKind = .squat, checkSize: Bool = true) -> FramingReport {
        guard let frame else {
            return FramingReport(ready: false, checks: [
                QualityCheck(id: "visible", label: "Widzę sylwetkę", passed: false, hint: "Stań przed kamerą, tak żeby było widać całą sylwetkę"),
            ], hint: "Stań przed kamerą, tak żeby było widać całą sylwetkę")
        }

        if kind != .squat { return assessUpperBody(frame, kind: kind, checkSize: checkSize) }

        let nose = frame.joint(.nose)
        let neck = frame.joint(.neck)
        let root = frame.joint(.root) ?? frame.joint(.leftHip) ?? frame.joint(.rightHip)
        let knee = frame.joint(.leftKnee) ?? frame.joint(.rightKnee)
        let ankles = [frame.joint(.leftAnkle), frame.joint(.rightAnkle)].compactMap { $0 }

        var checks: [QualityCheck] = []

        // Whole body visible.
        let feetOK = !ankles.isEmpty
        let headOK = nose != nil
        let bodyOK = feetOK && headOK && neck != nil && root != nil && knee != nil
        let bodyHint: String? = !feetOK ? "Odejdź krok do tyłu, nie widzę stóp"
            : !headOK ? "Przesuń telefon wyżej albo odejdź, nie widzę głowy"
            : !bodyOK ? "Odejdź kawałek, nie widzę całej sylwetki" : nil
        checks.append(QualityCheck(id: "full_body", label: "Cała sylwetka w kadrze", passed: bodyOK, hint: bodyHint))

        // Size in the frame.
        var sizeOK = false
        var sizeHint: String? = nil
        if let nose, let lowest = ankles.map(\.y).max() {
            let height = lowest - nose.y
            if height < minBodyHeight { sizeHint = "Podejdź bliżej, sylwetka jest za mała w kadrze" }
            else if height > maxBodyHeight { sizeHint = "Odejdź kawałek, sylwetka jest za blisko krawędzi" }
            else { sizeOK = true }
        } else {
            sizeHint = nil
        }
        if checkSize {
            checks.append(QualityCheck(id: "size", label: "Odpowiednia wielkość w kadrze", passed: sizeOK, hint: sizeHint))
        }

        // Side view.
        var sideOK = false
        var sideHint: String? = nil
        if let l = frame.joint(.leftShoulder), let r = frame.joint(.rightShoulder), let neck, let root {
            let torso = hypot(neck.x - root.x, neck.y - root.y)
            if torso > 0.02 {
                sideOK = abs(l.x - r.x) / torso <= maxShoulderRatio
                if !sideOK { sideHint = "Ustaw się bokiem do kamery" }
            }
        } else if bodyOK {
            // Only one shoulder visible: typical for a side view.
            sideOK = true
        }
        checks.append(QualityCheck(id: "side_view", label: "Ujęcie z boku", passed: sideOK, hint: sideHint))

        let hint = checks.first { !$0.passed }?.hint
        return FramingReport(ready: checks.allSatisfy(\.passed), checks: checks, hint: hint)
    }

    /// Summary for the end of a set from the per-frame results.
    public static func summarize(goodFrames: Int, totalFrames: Int, lastHint: String?) -> FramingSummary {
        guard totalFrames > 0 else { return FramingSummary(rating: .poor, goodFrameRatio: 0, hint: lastHint) }
        let ratio = Double(goodFrames) / Double(totalFrames)
        let rating: FramingRating = ratio >= 0.9 ? .good : ratio >= 0.7 ? .fair : .poor
        return FramingSummary(rating: rating, goodFrameRatio: ratio, hint: rating == .good ? nil : lastHint)
    }

    /// Push-up and pull-up: the whole person must be seen; a push-up is also checked for side view and size
    /// (the body is horizontal, so the size is its width).
    private static func assessUpperBody(_ frame: PoseFrame, kind: MovementKind, checkSize: Bool) -> FramingReport {
        let nose = frame.joint(.nose)
        let neck = frame.joint(.neck)
        let root = frame.joint(.root) ?? frame.joint(.leftHip) ?? frame.joint(.rightHip)
        let ankles = [frame.joint(.leftAnkle), frame.joint(.rightAnkle)].compactMap { $0 }
        let wrist = frame.joint(.leftWrist) ?? frame.joint(.rightWrist)

        var checks: [QualityCheck] = []
        let needFeet = kind == .pushup
        let bodyOK = nose != nil && neck != nil && root != nil && (!needFeet || !ankles.isEmpty) && wrist != nil
        let bodyHint: String? = nose == nil ? "Nie widzę głowy, ustaw telefon tak, żeby cała sylwetka była w kadrze"
            : (needFeet && ankles.isEmpty) ? "Odsuń telefon, nie widzę stóp"
            : wrist == nil ? "Nie widzę rąk, odsuń telefon albo ustaw go wyżej"
            : !bodyOK ? "Odejdź kawałek, nie widzę całej sylwetki" : nil
        checks.append(QualityCheck(id: "full_body", label: "Cała sylwetka w kadrze", passed: bodyOK, hint: bodyHint))

        if kind == .pushup, checkSize {
            var sizeOK = false
            var sizeHint: String? = nil
            let xs = ([nose, neck, root].compactMap { $0 } + ankles).map(\.x)
            if let minX = xs.min(), let maxX = xs.max() {
                let width = maxX - minX
                if width < minBodyHeight { sizeHint = "Podejdź bliżej, sylwetka jest za mała w kadrze" }
                else if width > maxBodyHeight { sizeHint = "Odsuń telefon, sylwetka nie mieści się w kadrze" }
                else { sizeOK = true }
            }
            checks.append(QualityCheck(id: "size", label: "Odpowiednia wielkość w kadrze", passed: sizeOK, hint: sizeHint))
        }

        if kind == .pushup, let l = frame.joint(.leftShoulder), let r = frame.joint(.rightShoulder), let neck, let root {
            let torso = hypot(neck.x - root.x, neck.y - root.y)
            if torso > 0.02 {
                let sideOK = abs(l.x - r.x) / torso <= maxShoulderRatio
                checks.append(QualityCheck(id: "side_view", label: "Ujęcie z boku", passed: sideOK,
                                           hint: sideOK ? nil : "Ustaw się bokiem do kamery"))
            }
        }

        let hint = checks.first { !$0.passed }?.hint
        return FramingReport(ready: checks.allSatisfy(\.passed), checks: checks, hint: hint)
    }
}
