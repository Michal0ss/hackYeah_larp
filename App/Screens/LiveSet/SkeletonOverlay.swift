import SwiftUI
import Contracts
import DesignSystem

/// Draws the detected skeleton over the video. Coordinates are normalized (0...1).
struct SkeletonOverlay: View {
    let frame: PoseFrame?

    private static let bones: [(JointName, JointName)] = [
        (.nose, .neck),
        (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.neck, .root),
        (.root, .leftHip), (.root, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    var body: some View {
        Canvas { context, size in
            guard let frame else { return }
            func point(_ name: JointName) -> CGPoint? {
                guard let j = frame.joint(name, minConfidence: 0.2) else { return nil }
                return CGPoint(x: j.x * size.width, y: j.y * size.height)
            }
            var path = Path()
            for (a, b) in Self.bones {
                if let pa = point(a), let pb = point(b) {
                    path.move(to: pa)
                    path.addLine(to: pb)
                }
            }
            context.addFilter(.shadow(color: FormaColor.volt.opacity(0.7), radius: 6))
            context.stroke(path, with: .color(FormaColor.volt), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            for joint in frame.joints where joint.confidence >= 0.2 {
                let p = CGPoint(x: joint.x * size.width, y: joint.y * size.height)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                             with: .color(.white))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
