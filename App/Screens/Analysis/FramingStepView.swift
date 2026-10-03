import SwiftUI
import DesignSystem

/// Step 2: how to position the phone before recording (PROJECT.md 5.3.2).
struct FramingStepView: View {
    let model: AnalysisModel

    private let tips: [(symbol: String, text: String)] = [
        ("arrow.left.and.right", "Ustaw telefon bokiem do siebie, nie z przodu"),
        ("ruler", "Na wysokości bioder, 2–3 metry od ćwiczącego"),
        ("figure.stand", "Cała sylwetka w kadrze — od głowy po kostki"),
        ("person.fill", "Jedna osoba w kadrze, bez innych w tle"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.l) {
            Text("Ustaw telefon")
                .formaStyle(.title)
                .foregroundStyle(FormaColor.ink)

            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(FormaColor.voltText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, FormaSpacing.xl)
                .glassCard()

            VStack(alignment: .leading, spacing: FormaSpacing.m) {
                ForEach(tips, id: \.text) { tip in
                    HStack(spacing: FormaSpacing.m) {
                        Image(systemName: tip.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(FormaColor.voltText)
                            .frame(width: 28)
                        Text(tip.text)
                            .formaStyle(.callout)
                            .foregroundStyle(FormaColor.ink2)
                    }
                }
            }
            .padding(FormaSpacing.l)
            .glassCard()

            Button {
                model.proceedFromFraming()
            } label: {
                Text("Gotowe, nagrywam")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.formaPrimary)
            .padding(.top, FormaSpacing.s)
        }
    }
}
