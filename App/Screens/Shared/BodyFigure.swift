import SwiftUI
import DesignSystem
import Plan

/// A white body, front or back, with the muscles that work drawn in red: full red for the muscles that do most of the
/// work, lighter red for the ones that help. Drawn from smooth curves in a 100 x 210 box, so it scales to any width.
struct BodyFigure: View {
    enum Side { case front, back }

    let side: Side
    let activation: MuscleMap.Activation

    private static let box = CGSize(width: 100, height: 210)

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / Self.box.width, size.height / Self.box.height)
            let origin = CGPoint(x: (size.width - Self.box.width * scale) / 2, y: (size.height - Self.box.height * scale) / 2)
            var drawing = BodyDrawing(context: context, scale: scale, origin: origin, activation: activation)
            drawing.body()
            if side == .front { drawing.front() } else { drawing.back() }
        }
        .aspectRatio(Self.box.width / Self.box.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// A path written the way SVG writes it, absolute `M x y`, `L x y`, `C x1 y1 x2 y2 x y` and `Z` only, in the 100 x 210
/// box. Drawn as written or mirrored left to right.
private struct CurvePath {
    private enum Step { case move(CGPoint), line(CGPoint), curve(CGPoint, CGPoint, CGPoint), close }
    private let steps: [Step]

    init(_ d: String) {
        var steps: [Step] = []
        let tokens = d.replacingOccurrences(of: ",", with: " ").split(separator: " ").map(String.init)
        var i = 0
        func number() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        func point() -> CGPoint { let x = number(); let y = number(); return CGPoint(x: x, y: y) }
        while i < tokens.count {
            let command = tokens[i]; i += 1
            switch command {
            case "M": steps.append(.move(point()))
            case "L": steps.append(.line(point()))
            case "C": let a = point(), b = point(), c = point(); steps.append(.curve(a, b, c))
            case "Z": steps.append(.close)
            default: break
            }
        }
        self.steps = steps
    }

    func path(mirrored: Bool, scale: CGFloat, origin: CGPoint) -> Path {
        func t(_ q: CGPoint) -> CGPoint {
            CGPoint(x: origin.x + (mirrored ? 100 - q.x : q.x) * scale, y: origin.y + q.y * scale)
        }
        var path = Path()
        for step in steps {
            switch step {
            case .move(let q): path.move(to: t(q))
            case .line(let q): path.addLine(to: t(q))
            case .curve(let a, let b, let c): path.addCurve(to: t(c), control1: t(a), control2: t(b))
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}

private struct BodyDrawing {
    var context: GraphicsContext
    let scale: CGFloat
    let origin: CGPoint
    let activation: MuscleMap.Activation

    private func shape(_ d: String, mirrored: Bool = false) -> Path {
        CurvePath(d).path(mirrored: mirrored, scale: scale, origin: origin)
    }

    /// The shape and its mirror image (left and right of the body).
    private func pair(_ d: String) -> [Path] { [shape(d), shape(d, mirrored: true)] }

    // MARK: body

    // Left half of the torso from the neck down the side to the crotch; the right half is its mirror image.
    private static let torsoLeft: [(String, [CGFloat])] = [
        ("C", [44, 31, 35, 33, 28, 40]),
        ("C", [25, 44, 27, 50, 30, 57]),
        ("C", [33, 66, 36, 78, 36, 92]),
        ("C", [36, 101, 33, 109, 32, 118]),
        ("C", [36, 124, 44, 127, 50, 127]),
    ]

    private func torso() -> Path {
        var anchors: [CGPoint] = [CGPoint(x: 50, y: 31)]
        for (_, v) in Self.torsoLeft { anchors.append(CGPoint(x: v[4], y: v[5])) }
        var d = "M 50 31"
        for (_, v) in Self.torsoLeft { d += " C " + v.map { String(describing: $0) }.joined(separator: " ") }
        // right half: the same curves walked backwards, mirrored
        for index in stride(from: Self.torsoLeft.count - 1, through: 0, by: -1) {
            let v = Self.torsoLeft[index].1
            let target = anchors[index]
            d += " C \(100 - v[2]) \(v[3]) \(100 - v[0]) \(v[1]) \(100 - target.x) \(target.y)"
        }
        d += " Z"
        return shape(d)
    }

    private static let head = "M 50 3 C 57 3 60 9 60 15 C 60 22 55 28 50 28 C 45 28 40 22 40 15 C 40 9 43 3 50 3 Z"
    private static let neck = "M 45.5 22 C 46 28 45 31 42 35 L 58 35 C 55 31 54 28 54.5 22 Z"
    private static let arm = """
        M 28 40 C 22 42 19 52 18 62 C 17 70 16 76 15 82 C 13 92 11 102 10 110 C 9 114 10 120 13 122 \
        C 16 121 17 116 18 112 C 20 104 23 94 25 84 C 27 76 30 66 32 56 C 33 50 32 44 28 40 Z
        """
    private static let leg = """
        M 33 116 C 30 130 31 148 35 164 C 33 172 32 182 35 192 C 36 198 36 202 36 204 C 33 206 30 208 32 209.5 \
        L 44 209.5 C 45 207 44 205 43 203 C 44 196 46 188 46 180 C 46 174 45 168 44 164 C 44 150 47 136 50 127 \
        C 44 124 38 120 33 116 Z
        """

    mutating func body() {
        var parts: [Path] = [shape(Self.head), torso()]
        parts += pair(Self.arm) + pair(Self.leg)
        // Soft shading: lighter in the middle of the body, a little darker towards the sides.
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [FormaColor.bodyShade, FormaColor.bodyFill, FormaColor.bodyFill, FormaColor.bodyShade]),
            startPoint: CGPoint(x: origin.x + 8 * scale, y: origin.y), endPoint: CGPoint(x: origin.x + 92 * scale, y: origin.y))
        for part in parts { context.fill(part, with: shading) }
        for part in parts { context.stroke(part, with: .color(FormaColor.bodyLine), style: StrokeStyle(lineWidth: 1.1 * scale, lineJoin: .round)) }
        // The neck sits on top of the torso: filled over the shoulder line, with its two sides drawn but not its base.
        let neck = shape(Self.neck)
        context.fill(neck, with: shading)
        var sides = Path()
        sides.move(to: CGPoint(x: origin.x + 45.5 * scale, y: origin.y + 22 * scale))
        sides.addCurve(to: CGPoint(x: origin.x + 42 * scale, y: origin.y + 35 * scale),
                       control1: CGPoint(x: origin.x + 46 * scale, y: origin.y + 28 * scale), control2: CGPoint(x: origin.x + 45 * scale, y: origin.y + 31 * scale))
        sides.move(to: CGPoint(x: origin.x + 54.5 * scale, y: origin.y + 22 * scale))
        sides.addCurve(to: CGPoint(x: origin.x + 58 * scale, y: origin.y + 35 * scale),
                       control1: CGPoint(x: origin.x + 54 * scale, y: origin.y + 28 * scale), control2: CGPoint(x: origin.x + 55 * scale, y: origin.y + 31 * scale))
        context.stroke(sides, with: .color(FormaColor.bodyLine), style: StrokeStyle(lineWidth: 1.1 * scale, lineCap: .round))
    }

    // MARK: muscles

    private func paint(_ muscle: Muscle, _ shapes: [Path]) {
        let load = activation[muscle]
        for shape in shapes {
            switch load {
            case .primary?:
                context.fill(shape, with: .linearGradient(Gradient(colors: [FormaColor.muscle, FormaColor.muscleDeep]),
                                                           startPoint: shape.boundingRect.origin,
                                                           endPoint: CGPoint(x: shape.boundingRect.maxX, y: shape.boundingRect.maxY)))
                context.stroke(shape, with: .color(FormaColor.muscleDeep.opacity(0.7)), lineWidth: 0.7 * scale)
            case .secondary?:
                context.fill(shape, with: .color(FormaColor.muscle.opacity(0.38)))
                context.stroke(shape, with: .color(FormaColor.muscle.opacity(0.55)), lineWidth: 0.7 * scale)
            case nil:
                context.stroke(shape, with: .color(FormaColor.bodyLine.opacity(0.75)), lineWidth: 0.7 * scale)
            }
        }
    }

    private static let deltoid = "M 28 40 C 23 42 21 50 23 57 C 27 57 31 54 32 50 C 33 46 31 42 28 40 Z"
    private static let pec = "M 49 46 C 44 44 37 45 33 50 C 33 58 38 64 44 63 C 47 62 49 60 49 56 Z"
    private static let biceps = "M 24 58 C 22 63 21 69 22 75 C 25 76 28 73 29 67 C 30 63 29 60 27 58 Z"
    private static let oblique = "M 39 67 C 36 73 36 85 38 96 C 41 94 43 88 43 80 C 43 74 42 70 39 67 Z"
    private static let quad = "M 40 128 C 35 136 32 150 35 162 C 39 165 43 163 44 158 C 46 146 46 136 45 129 C 44 126 41 126 40 128 Z"
    private static let absRows: [(String, String)] = (0..<4).map { row in
        let y = CGFloat(67 + row * 9)
        let inset = CGFloat(row) * 0.4
        let left = "M \(44 + inset) \(y) L 49.2 \(y) L 49.2 \(y + 7.4) C 46 \(y + 7.8) \(44 + inset) \(y + 6.5) \(44 + inset) \(y + 5) Z"
        return (left, "")
    }
    private static let trapezius = "M 50 32 C 44 34 38 37 33 41 C 36 48 42 56 50 66 C 58 56 64 48 67 41 C 62 37 56 34 50 32 Z"
    private static let lat = "M 49 66 C 43 62 37 60 34 62 C 33 72 36 84 42 90 C 46 90 48 88 49 84 Z"
    private static let lowerBack = "M 44 90 C 46 88 54 88 56 90 C 57 96 56 102 53 106 L 47 106 C 44 102 43 96 44 90 Z"
    private static let glute = "M 49 108 C 42 106 35 110 34 118 C 35 125 43 128 49 124 Z"
    private static let hamstring = "M 40 130 C 35 138 33 152 36 163 C 40 165 44 163 45 158 C 46 148 46 138 45 131 C 44 129 41 128 40 130 Z"
    private static let calf = "M 35 168 C 33 176 34 186 37 192 C 40 194 43 190 44 184 C 45 178 44 172 42 168 C 40 166 37 166 35 168 Z"

    mutating func front() {
        paint(.shoulders, pair(Self.deltoid))
        paint(.chest, pair(Self.pec))
        paint(.biceps, pair(Self.biceps))
        paint(.abs, Self.absRows.flatMap { pair($0.0) })
        paint(.obliques, pair(Self.oblique))
        paint(.quads, pair(Self.quad))
    }

    mutating func back() {
        paint(.shoulders, pair(Self.deltoid))
        paint(.upperBack, [shape(Self.trapezius)])
        paint(.triceps, pair(Self.biceps))
        paint(.lats, pair(Self.lat))
        paint(.lowerBack, [shape(Self.lowerBack)])
        paint(.glutes, pair(Self.glute))
        paint(.hamstrings, pair(Self.hamstring))
        paint(.calves, pair(Self.calf))
    }
}
