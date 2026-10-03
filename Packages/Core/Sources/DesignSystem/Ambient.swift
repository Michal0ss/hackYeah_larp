import SwiftUI

/// Rich background so glass has something to refract: gradient plus three soft glows.
public struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme

    public init() {}

    public var body: some View {
        let dark = scheme == .dark
        ZStack {
            LinearGradient(colors: [FormaColor.background2, FormaColor.background], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: 0xC8FF2E, opacity: dark ? 0.20 : 0.62), .clear],
                           center: UnitPoint(x: 1.05, y: -0.05), startRadius: 0, endRadius: 380)
            RadialGradient(colors: [dark ? Color(hex: 0x306EFF, opacity: 0.30) : Color(hex: 0x6EA0FF, opacity: 0.52), .clear],
                           center: UnitPoint(x: -0.15, y: 0.42), startRadius: 0, endRadius: 360)
            RadialGradient(colors: [dark ? Color(hex: 0xFF6A1F, opacity: 0.24) : Color(hex: 0xFFAA6E, opacity: 0.52), .clear],
                           center: UnitPoint(x: 0.92, y: 1.02), startRadius: 0, endRadius: 400)
        }
        .ignoresSafeArea()
    }
}
