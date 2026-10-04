import SwiftUI
import Contracts
import DesignSystem
import Plan

/// "Zaangażowane mięśnie": the body from the front and from the back with the muscles of one session in red, and the
/// names underneath (main ones, then the helping ones).
struct MuscleMapCard: View {
    @Environment(AppStore.self) private var store
    let session: PlannedSession

    private var activation: MuscleMap.Activation { MuscleMap.activation(for: session) { store.exercise(id: $0) } }

    private func names(_ load: MuscleLoad) -> String {
        Muscle.allCases.filter { activation[$0] == load }.map(\.title).joined(separator: ", ")
    }

    var body: some View {
        if !activation.isEmpty {
            VStack(alignment: .leading, spacing: FormaSpacing.m) {
                SectionLabel("Zaangażowane mięśnie")
                HStack(alignment: .top, spacing: FormaSpacing.l) {
                    figure(.front, "Przód")
                    figure(.back, "Tył")
                }
                .frame(maxWidth: .infinity)
                legend(.primary, "Główne", full: true)
                legend(.secondary, "Pomocnicze", full: false)
            }
            .padding(FormaSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Zaangażowane mięśnie. Główne: \(names(.primary)). Pomocnicze: \(names(.secondary)).")
        }
    }

    private func figure(_ side: BodyFigure.Side, _ title: String) -> some View {
        VStack(spacing: FormaSpacing.xs) {
            BodyFigure(side: side, activation: activation)
                .frame(maxHeight: 280)
            Text(title).formaStyle(.caption).foregroundStyle(FormaColor.ink3)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func legend(_ load: MuscleLoad, _ title: String, full: Bool) -> some View {
        let text = names(load)
        if !text.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: FormaSpacing.s) {
                Circle().fill(FormaColor.muscle.opacity(full ? 1 : 0.42)).frame(width: 10, height: 10)
                Text("\(title): ").font(.system(size: 15, weight: .semibold)).foregroundStyle(FormaColor.ink)
                    + Text(text).font(.system(size: 15)).foregroundStyle(FormaColor.ink2)
            }
        }
    }
}
