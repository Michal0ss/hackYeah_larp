import SwiftUI
import DesignSystem

/// What the technique assessment adapted to the person (mobility, level, an earlier injury, proportions), or, when
/// nothing was adapted, a pointer to where it can be set. The notes are shown here only: they are not stored with the
/// result and never leave the phone.
struct ContextNoteView: View {
    let notes: [String]

    var body: some View {
        if notes.isEmpty {
            Label("Ocena według standardu. Możesz dopasować ją do swojej mobilności w Profilu.", systemImage: "slider.horizontal.3")
                .formaStyle(.footnote)
                .foregroundStyle(FormaColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: FormaSpacing.s) {
                Label("Dopasowano do Ciebie", systemImage: "slider.horizontal.3")
                    .formaStyle(.callout).fontWeight(.semibold).foregroundStyle(FormaColor.ink)
                ForEach(notes, id: \.self) { note in
                    Text(note)
                        .formaStyle(.footnote)
                        .foregroundStyle(FormaColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(FormaSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .accessibilityElement(children: .combine)
        }
    }
}
