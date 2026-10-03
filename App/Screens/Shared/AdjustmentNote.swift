import SwiftUI
import Contracts
import DesignSystem
import Insights

/// Why today's session differs from the plan, what changed, and the way back to the original.
struct AdjustmentNote: View {
    let adjustment: PlanAdjustment
    let restored: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.s) {
            if adjustment.isChanged {
                if let note = adjustment.session.adaptationNote {
                    Text(note).formaStyle(.subheadline).foregroundStyle(FormaColor.ink2)
                }
                ForEach(adjustment.changes, id: \.self) { line in
                    Label(line, systemImage: "arrow.right")
                        .font(.system(size: 13)).foregroundStyle(FormaColor.ink3)
                        .labelStyle(.titleAndIcon)
                }
            }
            if adjustment.isChanged || restored {
                Button(action: onToggle) {
                    Text(restored ? "Zastosuj rekomendację" : "Przywróć oryginał")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FormaColor.voltText)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
