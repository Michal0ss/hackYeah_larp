import SwiftUI

// Design tokens taken from the clickable prototype "Forma — prototyp iOS".
// Dark is the default look (gym vibe), light is the second theme.

public extension Color {
    /// `0xRRGGBB` in sRGB.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// A color that follows the light/dark appearance.
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
        #elseif canImport(AppKit)
        self = Color(NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(dark) : NSColor(light) })
        #else
        self = dark
        #endif
    }
}

public enum FormaColor {
    // Surfaces and text (follow appearance)
    public static let background = Color(light: Color(hex: 0xE9EEF4), dark: Color(hex: 0x0B0F14))
    public static let background2 = Color(light: Color(hex: 0xF5F8FB), dark: Color(hex: 0x121B28))
    public static let ink = Color(light: Color(hex: 0x0B1118), dark: Color(hex: 0xF4F7FB))
    public static let ink2 = Color(light: Color(hex: 0x0B1118, opacity: 0.78), dark: Color(hex: 0xEEF4FC, opacity: 0.78))
    public static let ink3 = Color(light: Color(hex: 0x0B1118, opacity: 0.66), dark: Color(hex: 0xEEF4FC, opacity: 0.62))
    public static let line = Color(light: Color(hex: 0x0B1118, opacity: 0.10), dark: Color.white.opacity(0.11))
    public static let well = Color(light: Color.white.opacity(0.58), dark: Color.white.opacity(0.065))
    public static let wellLine = Color(light: Color(hex: 0x0B1118, opacity: 0.07), dark: Color.white.opacity(0.09))

    // Brand and state fills (fixed)
    public static let volt = Color(hex: 0xC8FF2E)
    public static let onVolt = Color(hex: 0x0B0F14)
    public static let ember = Color(hex: 0xFF6A1F)
    /// Muscles worked on the body figure (red), and the white body they are drawn on.
    public static let muscle = Color(hex: 0xE5262F)
    public static let muscleDeep = Color(hex: 0xA8141C)
    public static let bodyFill = Color(hex: 0xF7F8FA)
    public static let bodyShade = Color(hex: 0xD9DFE7)
    public static let bodyLine = Color(hex: 0xB9C2CF)
    public static let go = Color(hex: 0xC8FF2E)
    public static let moderate = Color(hex: 0xFFBE3D)
    public static let rest = Color(hex: 0x63B3FF)

    // Readable variants for text on glass (follow appearance, WCAG AA)
    public static let voltText = Color(light: Color(hex: 0x476F00), dark: Color(hex: 0xC8FF2E))
    public static let emberText = Color(light: Color(hex: 0xB23F07), dark: Color(hex: 0xFF8B4F))
    public static let goText = voltText
    public static let moderateText = Color(light: Color(hex: 0x8A5200), dark: Color(hex: 0xFFC85C))
    public static let restText = Color(light: Color(hex: 0x14569F), dark: Color(hex: 0x7DC0FF))
}

public enum FormaRadius {
    public static let xl: CGFloat = 36
    public static let lg: CGFloat = 28
    public static let md: CGFloat = 18
    public static let sm: CGFloat = 12
}

public enum FormaSpacing {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 20
    public static let xxl: CGFloat = 28
    /// Horizontal screen margin.
    public static let screen: CGFloat = 20
}
