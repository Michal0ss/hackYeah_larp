import SwiftUI
import Contracts
import DesignSystem

/// Draws the detected skeleton over the video. Coordinates are normalized (0...1).
struct SkeletonOverlay: View {
    let frame: PoseFrame?
    /// Colours joints by Vision's confidence (green, yellow, red) and prints short names.
    var debug = false

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
            for joint in frame.joints where debug || joint.confidence >= 0.2 {
                let p = CGPoint(x: joint.x * size.width, y: joint.y * size.height)
                let color: Color = !debug ? .white : joint.confidence >= 0.6 ? .green : joint.confidence >= 0.2 ? .yellow : .red
                context.fill(Path(ellipseIn: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)), with: .color(color))
                if debug {
                    context.draw(Text(Self.shortName(joint.name)).font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white), at: CGPoint(x: p.x + 16, y: p.y - 8))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func shortName(_ name: JointName) -> String {
        switch name {
        case .nose: return "nos"
        case .neck: return "kark"
        case .leftShoulder: return "L bark"
        case .rightShoulder: return "P bark"
        case .leftElbow: return "L łok"
        case .rightElbow: return "P łok"
        case .leftWrist: return "L nadg"
        case .rightWrist: return "P nadg"
        case .root: return "biodra"
        case .leftHip: return "L bio"
        case .rightHip: return "P bio"
        case .leftKnee: return "L kol"
        case .rightKnee: return "P kol"
        case .leftAnkle: return "L kost"
        case .rightAnkle: return "P kost"
        }
    }
}
