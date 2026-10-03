import SwiftUI
import DesignSystem

/// Temporary screen for modules that are not built yet. Each owner replaces it.
struct PlaceholderScreen: View {
    let title: String
    let owner: String
    let summary: String
    let symbol: String

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: FormaSpacing.l) {
                Image(systemName: symbol)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(FormaColor.voltText)
                Text(title).formaStyle(.title).foregroundStyle(FormaColor.ink)
                Text(summary)
                    .formaStyle(.callout)
                    .foregroundStyle(FormaColor.ink2)
                    .multilineTextAlignment(.center)
                Text("Odpowiada: \(owner)")
                    .formaStyle(.caption)
                    .foregroundStyle(FormaColor.ink3)
            }
            .padding(FormaSpacing.xxl)
            .glassCard()
            .padding(.horizontal, FormaSpacing.screen)
        }
    }
}
