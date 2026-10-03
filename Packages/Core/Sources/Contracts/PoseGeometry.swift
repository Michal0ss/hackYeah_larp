import Foundation

/// Lengths and angles of a pose as real geometry.
///
/// Vision gives every joint as a fraction of the image width (x) and of the image height (y). A portrait video is
/// 9:16, so one unit of x is a much shorter distance than one unit of y, and a 45 degree line looks like 29 degrees.
/// Everything here first turns x into "image-height units" (`x * aspect`), where distances and angles are true.
public enum PoseGeometry {
    /// Angle at `b` between `a-b` and `c-b`, in degrees (180 = a straight line).
    public static func angle(_ a: Joint, _ b: Joint, _ c: Joint, aspect: Double = 1) -> Double {
        let v1 = (x: (a.x - b.x) * aspect, y: a.y - b.y)
        let v2 = (x: (c.x - b.x) * aspect, y: c.y - b.y)
        let dot = v1.x * v2.x + v1.y * v2.y
        let norm = hypot(v1.x, v1.y) * hypot(v2.x, v2.y)
        guard norm > 0 else { return 180 }
        return acos(min(1, max(-1, dot / norm))) * 180 / .pi
    }

    /// Angle between the vector `from -> to` and the vertical, in degrees (0 = straight up or down).
    public static func angleFromVertical(from: Joint, to: Joint, aspect: Double = 1) -> Double {
        atan2(abs(to.x - from.x) * aspect, abs(to.y - from.y)) * 180 / .pi
    }

    /// Distance between two joints in image-height units.
    public static func distance(_ a: Joint, _ b: Joint, aspect: Double = 1) -> Double {
        hypot((a.x - b.x) * aspect, a.y - b.y)
    }
}

public extension PoseFrame {
    /// `aspect`, or 1 when unknown or nonsensical.
    var aspectRatio: Double {
        guard let aspect, aspect > 0.1, aspect < 10 else { return 1 }
        return aspect
    }

    func angle(_ a: Joint, _ b: Joint, _ c: Joint) -> Double {
        PoseGeometry.angle(a, b, c, aspect: aspectRatio)
    }

    func angleFromVertical(from: Joint, to: Joint) -> Double {
        PoseGeometry.angleFromVertical(from: from, to: to, aspect: aspectRatio)
    }

    func distance(_ a: Joint, _ b: Joint) -> Double {
        PoseGeometry.distance(a, b, aspect: aspectRatio)
    }
}
