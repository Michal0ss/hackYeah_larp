import SwiftUI
import Contracts
import DesignSystem
import Onboarding

/// Title and subtitle at the top of a step.
struct OnboardingHeader: View {
    var overline: String?
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let overline {
                SectionLabel(overline)
            }
            Text(title)
                .formaStyle(.title)
                .foregroundStyle(FormaColor.ink)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .formaStyle(.callout)
                    .foregroundStyle(FormaColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Glass card with a title row.
struct OnboardingSection<Trailing: View, Content: View>: View {
    let title: String
    let trailing: Trailing
    let content: Content

    init(_ title: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).formaStyle(.headline).foregroundStyle(FormaColor.ink)
                Spacer()
                trailing
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

extension OnboardingSection where Trailing == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, trailing: { EmptyView() }, content: content)
    }
}

// MARK: - Labels and icons

extension TrainingGoal {
    var title: String {
        switch self {
        case .strength: return "Siła"
        case .physique: return "Sylwetka"
        case .fitness: return "Kondycja"
        case .returnToMovement: return "Powrót do ruchu"
        }
    }

    var subtitle: String {
        switch self {
        case .strength: return "Cięższe serie, mniej powtórzeń"
        case .physique: return "Mięśnie i proporcje"
        case .fitness: return "Wytrzymałość i energia"
        case .returnToMovement: return "Spokojnie, krok po kroku"
        }
    }

    var symbol: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .physique: return "figure.arms.open"
        case .fitness: return "figure.run"
        case .returnToMovement: return "figure.walk"
        }
    }
}

extension TrainingLevel {
    var title: String {
        switch self {
        case .beginner: return "Początkujący"
        case .intermediate: return "Średni"
        }
    }
}

extension GearItem {
    var title: String {
        switch self {
        case .none: return "Bez sprzętu"
        case .dumbbells: return "Hantle"
        case .kettlebell: return "Kettlebell"
        case .gym: return "Siłownia"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "figure.stand"
        case .dumbbells: return "dumbbell.fill"
        case .kettlebell: return "scalemass.fill"
        case .gym: return "building.2.fill"
        }
    }
}
