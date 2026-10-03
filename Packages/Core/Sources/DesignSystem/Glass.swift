import SwiftUI

// Glass surfaces. iOS 26 uses the system Liquid Glass; older systems get a blur material
// with a bright rim, so the look stays close but without refraction.

private struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if interactive {
                content.glassEffect(.regular.interactive(), in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        } else {
            content
                .background { shape.fill(.ultraThinMaterial) }
                .overlay {
                    shape.strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.07), .white.opacity(0.24)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
        }
    }
}

public extension View {
    /// Glass card with a rounded rectangle.
    func glassCard(radius: CGFloat = FormaRadius.lg) -> some View {
        modifier(GlassSurface(shape: RoundedRectangle(cornerRadius: radius, style: .continuous), interactive: false))
    }

    /// Glass pill for buttons and chips.
    func glassCapsule(interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: Capsule(style: .continuous), interactive: interactive))
    }
}
