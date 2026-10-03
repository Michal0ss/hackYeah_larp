import SwiftUI
import LiveSet
import DesignSystem

/// Step 2: how to position the phone before recording (PROJECT.md 5.3.2), tailored to the chosen
/// exercise (squat/push-up/pull-up each need a different setup — reuses the live set's own copy).
struct FramingStepView: View {
    let model: AnalysisModel

    private var symbol: String {
        switch model.kind {
        case .squat: return "figure.strengthtraining.traditional"
        case .pushup: return "figure.cross.training"
        case .pullup: return "figure.climbing"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.l) {
            Text("Ustaw telefon — \(model.kind.title.lowercased())")
                .formaStyle(.title)
                .foregroundStyle(FormaColor.ink)

            Image(systemName: symbol)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(FormaColor.voltText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, FormaSpacing.xl)
                .glassCard()

            Text(model.kind.setupHint)
                .formaStyle(.callout)
                .foregroundStyle(FormaColor.ink2)
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
