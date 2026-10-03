import Contracts
import DesignSystem
import SwiftUI

/// A change of the plan that the coach proposes. The plan changes only when the user taps "Zastosuj"; the coach's own
/// words are shown as a quote, the description of the change is written by the app.
struct PlanProposalCard: View {
    let proposal: PlanChangeProposal
    /// Why the last tap did not work (the plan changed in the meantime, ...).
    let error: String?
    let onApply: () -> Void
    let onDismiss: () -> Void
    let onUndo: () -> Void
    let onShowPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            HStack(spacing: FormaSpacing.s) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .accessibilityHidden(true)
                Text(statusTitle).formaStyle(.caption).foregroundStyle(FormaColor.ink3)
            }
            Text(verbatim: proposal.summary)
                .formaStyle(.headline).foregroundStyle(FormaColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let reason = proposal.reason {
                Text(verbatim: "„\(reason)”")
                    .formaStyle(.footnote).foregroundStyle(FormaColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .formaStyle(.footnote).foregroundStyle(FormaColor.moderateText)
                    .labelStyle(.titleAndIcon)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .padding(FormaSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 22)
        .padding(.trailing, 20)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actions: some View {
        switch proposal.status {
        case .pending:
            HStack(spacing: FormaSpacing.s) {
                Button(action: onApply) { Text("Zastosuj").frame(maxWidth: .infinity) }
                    .buttonStyle(.formaPrimary)
                Button(action: onDismiss) { Text("Odrzuć").frame(maxWidth: .infinity) }
                    .buttonStyle(.formaGlass)
            }
        case .applied:
            HStack(spacing: FormaSpacing.l) {
                Button("Zobacz w planie", action: onShowPlan)
                Button("Cofnij", action: onUndo)
            }
            .formaStyle(.subheadline)
            .foregroundStyle(FormaColor.voltText)
            .buttonStyle(.plain)
        case .dismissed, .undone:
            EmptyView()
        }
    }

    private var statusTitle: String {
        switch proposal.status {
        case .pending: return "Propozycja zmiany planu"
        case .applied: return "Zastosowano w planie"
        case .dismissed: return "Propozycja odrzucona"
        case .undone: return "Zmiana cofnięta"
        }
    }

    private var icon: String {
        switch proposal.status {
        case .pending: return "arrow.triangle.2.circlepath"
        case .applied: return "checkmark.circle.fill"
        case .dismissed: return "xmark.circle"
        case .undone: return "arrow.uturn.backward.circle"
        }
    }

    private var statusColor: Color {
        proposal.status == .applied || proposal.status == .pending ? FormaColor.voltText : FormaColor.ink3
    }
}
