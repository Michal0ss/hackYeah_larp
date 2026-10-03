import SwiftUI

/// Main action: volt gradient pill.
public struct FormaPrimaryButtonStyle: ButtonStyle {
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
            .shadow(color: FormaColor.volt.opacity(0.45), radius: 14, y: 8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Secondary action: glass pill.
public struct FormaGlassButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(FormaColor.ink)
            .padding(.horizontal, 22)
            .frame(minHeight: 52)
            .glassCapsule(interactive: true)
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
