import SwiftUI
import DesignSystem

/// Step 5: scoring is running (fast — extraction already happened during the quality check).
struct ProcessingStepView: View {
    var body: some View {
        VStack(spacing: FormaSpacing.l) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Liczę wynik…")
                .formaStyle(.headline)
                .foregroundStyle(FormaColor.ink)
            Text("Powtórzenia, kąty, tempo.")
                .formaStyle(.footnote)
                .foregroundStyle(FormaColor.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(FormaSpacing.xxl)
        .glassCard()
        .padding(.top, FormaSpacing.xxl)
    }
}
