import SwiftUI
import DesignSystem
import Plan

/// A white body, front or back, with the muscles that work drawn in red: full red for the muscles that do most of the
/// work, lighter red for the ones that help. Drawn in a 100 x 210 box, so it scales to any width.
struct BodyFigure: View {
    enum Side { case front, back }

    let side: Side
    let activation: MuscleMap.Activation

    private static let box = CGSize(width: 100, height: 210)

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / Self.box.width, size.height / Self.box.height)
            let origin = CGPoint(x: (size.width - Self.box.width * scale) / 2, y: (size.height - Self.box.height * scale) / 2)
            var drawing = Drawing(context: context, scale: scale, origin: origin, activation: activation)
            drawing.silhouette()
            if side == .front { drawing.front() } else { drawing.back() }
        }
        .aspectRatio(Self.box.width / Self.box.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct Drawing {
    var context: GraphicsContext
    let scale: CGFloat
    let origin: CGPoint
    let activation: MuscleMap.Activation

    private func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * scale, y: origin.y + y * scale) }

    private func limb(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), width: CGFloat) -> Path {
        var path = Path()
        path.move(to: p(a.0, a.1))
        path.addLine(to: p(b.0, b.1))
        return path.strokedPath(StrokeStyle(lineWidth: width * scale, lineCap: .round))
    }

    private func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: origin.x + (cx - rx) * scale, y: origin.y + (cy - ry) * scale, width: 2 * rx * scale, height: 2 * ry * scale))
    }

    private func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        var path = Path()
        path.move(to: p(points[0].0, points[0].1))
        for point in points.dropFirst() { path.addLine(to: p(point.0, point.1)) }
        path.closeSubpath()
        return path.strokedPath(StrokeStyle(lineWidth: 3 * scale, lineJoin: .round)).union(path)
    }

    private func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat = 3) -> Path {
        Path(roundedRect: CGRect(x: origin.x + x * scale, y: origin.y + y * scale, width: w * scale, height: h * scale),
             cornerRadius: radius * scale)
    }

    private func mirrored(_ x: CGFloat) -> CGFloat { 100 - x }

    // MARK: body

    mutating func silhouette() {
        var parts: [Path] = [
            ellipse(50, 15, 9, 11),
            polygon([(46, 24), (54, 24), (54, 34), (46, 34)]),
            polygon([(31, 38), (69, 38), (72, 56), (66, 80), (63, 100), (68, 122), (32, 122), (37, 100), (34, 80), (28, 56)]),
        ]
        for side in [false, true] {
            func x(_ v: CGFloat) -> CGFloat { side ? mirrored(v) : v }
            parts.append(limb((x(27), 43), (x(19), 80), width: 10))      // upper arm
            parts.append(limb((x(19), 80), (x(14), 112), width: 8))      // forearm
            parts.append(ellipse(x(13), 118, 4.5, 5.5))                  // hand
            parts.append(limb((x(40), 124), (x(38), 166), width: 17))    // thigh
            parts.append(limb((x(38), 166), (x(38), 202), width: 11))    // shin
            parts.append(ellipse(x(37), 206, 6.5, 3))                    // foot
        }
        for part in parts { context.stroke(part, with: .color(FormaColor.bodyLine), lineWidth: 1.4 * scale) }
        for part in parts { context.fill(part, with: .color(FormaColor.bodyFill)) }
    }

    // MARK: muscles

    private func paint(_ muscle: Muscle, _ shapes: [Path]) {
        let load = activation[muscle]
        let color: Color
        let outline: Color
        switch load {
        case .primary?: color = FormaColor.muscle; outline = FormaColor.muscle
        case .secondary?: color = FormaColor.muscle.opacity(0.42); outline = FormaColor.muscle.opacity(0.6)
        case nil: color = .clear; outline = FormaColor.bodyLine.opacity(0.8)
        }
        for shape in shapes {
            if load != nil { context.fill(shape, with: .color(color)) }
            context.stroke(shape, with: .color(outline), lineWidth: (load == nil ? 0.8 : 1.0) * scale)
        }
    }

    private func pair(_ build: (_ x: (CGFloat) -> CGFloat) -> Path) -> [Path] {
        [build { $0 }, build { mirrored($0) }]
    }

    mutating func front() {
        paint(.shoulders, pair { x in ellipse(x(30), 43, 6.5, 6.5) })
        paint(.chest, pair { x in polygon([(x(48), 45), (x(36), 46), (x(34), 56), (x(40), 62), (x(48), 61)]) })
        paint(.biceps, pair { x in limb((x(25), 50), (x(21), 72), width: 6.5) })
        paint(.abs, (0..<4).flatMap { row in
            let y = CGFloat(66 + row * 9)
            return [roundedRect(43.5, y, 6, 7.5, radius: 2), roundedRect(50.5, y, 6, 7.5, radius: 2)]
        })
        paint(.obliques, pair { x in limb((x(39.5), 68), (x(37.5), 100), width: 4.5) })
        paint(.quads, pair { x in limb((x(41), 130), (x(39), 160), width: 12.5) })
    }

    mutating func back() {
        paint(.shoulders, pair { x in ellipse(x(30), 43, 6.5, 6.5) })
        paint(.upperBack, [polygon([(50, 34), (62, 42), (58, 58), (50, 62), (42, 58), (38, 42)])])
        paint(.triceps, pair { x in limb((x(25), 50), (x(21), 72), width: 6.5) })
        paint(.lats, pair { x in polygon([(x(41), 60), (x(48), 64), (x(47), 86), (x(41), 87), (x(36), 70)]) })
        paint(.lowerBack, [roundedRect(43.5, 89, 13, 16, radius: 3)])
        paint(.glutes, pair { x in ellipse(x(43.5), 115, 8, 8.5) })
        paint(.hamstrings, pair { x in limb((x(41), 134), (x(39), 160), width: 12.5) })
        paint(.calves, pair { x in limb((x(38), 174), (x(38), 194), width: 9) })
    }
}
