import SwiftUI

public extension Font {
    /// Big scoreboard numbers: SF Pro Expanded, heavy.
    static func formaNumber(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy).width(.expanded)
    }
}

public enum FormaTextStyle {
    case largeTitle, title, title2, headline, body, callout, subheadline, footnote, caption

    /// Semantic styles: same sizes as before at the default setting, but they follow Dynamic Type.
    var font: Font {
        switch self {
        case .largeTitle: return .system(.largeTitle, weight: .bold)
        case .title: return .system(.title, weight: .bold)
        case .title2: return .system(.title2, weight: .semibold)
        case .headline: return .system(.headline)
        case .body: return .system(.body)
        case .callout: return .system(.callout)
        case .subheadline: return .system(.subheadline)
        case .footnote: return .system(.footnote)
        case .caption: return .system(.caption, weight: .bold)
        }
    }
}

public extension View {
    /// Applies a Forma text style. `.caption` is uppercase with wide tracking.
    @ViewBuilder
    func formaStyle(_ style: FormaTextStyle) -> some View {
        if style == .caption {
            self.font(style.font).tracking(0.9).textCase(.uppercase)
        } else {
            self.font(style.font)
        }
    }
}

/// A scoreboard number with an optional unit, e.g. `72` or `5 h 40 min` pieces.
public struct NumberText: View {
    private let value: String
    private let size: CGFloat
    private let unit: String?
    private let color: Color

    public init(_ value: String, size: CGFloat = 40, unit: String? = nil, color: Color = FormaColor.ink) {
        self.value = value
        self.size = size
        self.unit = unit
        self.color = color
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.formaNumber(size))
                .monospacedDigit()
                .foregroundStyle(color)
            if let unit {
                Text(unit)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FormaColor.ink3)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
