import SwiftUI

/// Main action: volt gradient pill.
public struct FormaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(FormaColor.onVolt)
            .padding(.horizontal, 22)
            .frame(minHeight: 52)
            .background(
                LinearGradient(colors: [Color(hex: 0xDDFF70), FormaColor.volt, Color(hex: 0xB8F01C)],
                               startPoint: .top, endPoint: .bottom),
                in: Capsule(style: .continuous))
            .shadow(color: FormaColor.volt.opacity(isEnabled ? 0.45 : 0), radius: 14, y: 8)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Secondary action: glass pill.
public struct FormaGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(FormaColor.ink)
            .padding(.horizontal, 22)
            .frame(minHeight: 52)
            .glassCapsule(interactive: true)
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == FormaPrimaryButtonStyle {
    static var formaPrimary: FormaPrimaryButtonStyle { FormaPrimaryButtonStyle() }
}

public extension ButtonStyle where Self == FormaGlassButtonStyle {
    static var formaGlass: FormaGlassButtonStyle { FormaGlassButtonStyle() }
}

/// Subtle press feedback for tiles and rows.
public struct FormaPressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == FormaPressStyle {
    static var formaPress: FormaPressStyle { FormaPressStyle() }
}
