import Contracts
import DesignSystem
import Insights
import SwiftUI

/// Under an answer in which the coach suggests talking to a specialist (PROJECT.md 5.8): the coach chooses the moment
/// (the tool `suggest_consultation`), and the card also appears when the question has a plain word about pain or an
/// injury, whatever the model does. A signal to talk to a specialist, never a diagnosis.
struct ConsultationCard: View {
    @State private var showPhysio = false

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            HStack(spacing: FormaSpacing.s) {
                Image(systemName: "info.circle.fill").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FormaColor.restText).accessibilityHidden(true)
                Text("Warto rozważyć konsultację").formaStyle(.caption).foregroundStyle(FormaColor.ink3)
            }
            Text("Trener nie ocenia, co się dzieje. Warto porozmawiać ze specjalistą, np. fizjoterapeutą, który oceni to na żywo.")
                .formaStyle(.subheadline).foregroundStyle(FormaColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(CarePathway.disclaimer)
                .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
            Button { showPhysio = true } label: {
                Label("Znajdź fizjoterapeutę w pobliżu", systemImage: "mappin.and.ellipse").frame(maxWidth: .infinity)
            }
            .buttonStyle(.formaPrimary)
        }
        .padding(FormaSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 22)
        .padding(.trailing, 20)
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showPhysio) { NavigationStack { PhysioResultsView() } }
    }
}
