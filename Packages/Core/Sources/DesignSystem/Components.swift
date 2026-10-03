import SwiftUI
import Contracts

public extension Decision {
    /// Fill color of the state.
    var color: Color {
        switch self {
        case .train: return FormaColor.go
        case .adapt: return FormaColor.moderate
        case .rest: return FormaColor.rest
        }
    }

    /// Readable text color on glass.
    var textColor: Color {
        switch self {
        case .train: return FormaColor.goText
        case .adapt: return FormaColor.moderateText
        case .rest: return FormaColor.restText
        }
    }

    /// State is never shown by color alone: there is always an icon and a word.
    var symbol: String {
        switch self {
        case .train: return "bolt.fill"
        case .adapt: return "slider.horizontal.3"
        case .rest: return "moon.zzz.fill"
        }
    }
}

/// "Trenuj / Zmodyfikuj / Odpuść" badge.
public struct DecisionChip: View {
    private let decision: Decision

    public init(_ decision: Decision) {
        self.decision = decision
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: decision.symbol)
                .font(.system(size: 13, weight: .bold))
            Text(decision.title)
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(decision.textColor)
        .padding(.leading, 9)
        .padding(.trailing, 12)
        .frame(height: 30)
        .background(decision.color.opacity(0.17), in: Capsule())
        .overlay { Capsule().strokeBorder(decision.color.opacity(0.4), lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

/// Mandatory marker for simulated data.
public struct SimulatedBadge: View {
    public init() {}

    public var body: some View {
        Text("Dane przykładowe")
            .font(.system(size: 11, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(FormaColor.ink3)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(FormaColor.well, in: Capsule())
            .overlay { Capsule().strokeBorder(FormaColor.line, lineWidth: 1) }
    }
}

/// Activity-style progress ring.
public struct ProgressRing<Content: View>: View {
    private let progress: Double
    private let lineWidth: CGFloat
    private let color: Color
    private let content: Content

    public init(progress: Double, lineWidth: CGFloat = 10, color: Color = FormaColor.volt,
                @ViewBuilder content: () -> Content) {
        self.progress = min(max(progress, 0), 1)
        self.lineWidth = lineWidth
        self.color = color
        self.content = content()
    }

    public var body: some View {
        ZStack {
            Circle().stroke(FormaColor.ink.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.5), radius: 6)
            content
        }
        .animation(.easeOut(duration: 0.6), value: progress)
    }
}

/// Small uppercase section label.
public struct SectionLabel: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .formaStyle(.caption)
            .foregroundStyle(FormaColor.ink3)
    }
}
