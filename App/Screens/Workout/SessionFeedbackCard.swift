import SwiftUI
import Contracts
import DesignSystem
import LiveSet

/// What the user has filled in so far on the end screen of a workout.
struct SessionFeedbackDraft: Equatable {
    var exertion: Int?
    var hasPain = false
    var pain: [PainArea: Int] = [:]
    var note = ""

    static let maxNoteLength = 300

    /// Nil when nothing was said: skipping the card saves nothing.
    func build(sessionId: UUID, completedSets: Int, plannedSets: Int) -> SessionFeedback? {
        guard let exertion else { return nil }
        let reports = hasPain ? PainArea.allCases.compactMap { area in pain[area].map { PainReport(area: area, intensity: $0) } } : []
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return SessionFeedback(sessionId: sessionId, perceivedExertion: exertion, pain: reports,
                               note: text.isEmpty ? nil : String(text.prefix(Self.maxNoteLength)),
                               completedSets: completedSets, plannedSets: plannedSets)
    }
}

/// "Jak poszło?": effort (RPE 1-10), where it hurt (optional) and a note. It stays on the phone; the coach reads it
/// only after the user agreed to share health data. Effort is required to save anything, the rest is optional.
struct SessionFeedbackCard: View {
    @Binding var draft: SessionFeedbackDraft
    let sessionId: UUID
    let completedSets: Int
    let plannedSets: Int

    private let columns = Array(repeating: GridItem(.flexible(), spacing: FormaSpacing.s), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.l) {
            SectionLabel("Jak poszło?")
            VStack(alignment: .leading, spacing: FormaSpacing.s) {
                Text("Wysiłek").formaStyle(.headline).foregroundStyle(FormaColor.ink)
                LazyVGrid(columns: columns, spacing: FormaSpacing.s) {
                    ForEach(1...10, id: \.self) { value in
                        chip("\(value)", selected: draft.exertion == value) {
                            draft.exertion = draft.exertion == value ? nil : value
                        }
                        .accessibilityLabel("Wysiłek \(value) z 10")
                    }
                }
                Text("1 = bardzo lekko, 10 = maksymalny wysiłek").formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                if let preview = preview {
                    Text(preview).formaStyle(.subheadline).foregroundStyle(FormaColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle(isOn: $draft.hasPain) {
                Text("Coś bolało lub uwierało?").formaStyle(.headline).foregroundStyle(FormaColor.ink)
            }
            .tint(FormaColor.volt)
            if draft.hasPain { painPicker }

            VStack(alignment: .leading, spacing: FormaSpacing.s) {
                Text("Uwagi (opcjonalnie)").formaStyle(.headline).foregroundStyle(FormaColor.ink)
                TextField("Np. za ciężko w ostatniej serii", text: $draft.note, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(FormaSpacing.m)
                    .background(FormaColor.well, in: RoundedRectangle(cornerRadius: FormaRadius.sm, style: .continuous))
                    .foregroundStyle(FormaColor.ink)
                    .onChange(of: draft.note) { _, value in
                        if value.count > SessionFeedbackDraft.maxNoteLength { draft.note = String(value.prefix(SessionFeedbackDraft.maxNoteLength)) }
                    }
            }
            Text("Zostaje na telefonie. Trener zobaczy to tylko po Twojej zgodzie na dane zdrowotne.")
                .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
        }
        .padding(FormaSpacing.xl).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private var preview: String? {
        draft.build(sessionId: sessionId, completedSets: completedSets, plannedSets: plannedSets).map(SessionFeedbackText.summary(for:))
    }

    private var painPicker: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            Text("Gdzie? Ból to sygnał, nie diagnoza.").formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: FormaSpacing.s)], alignment: .leading, spacing: FormaSpacing.s) {
                ForEach(PainArea.allCases, id: \.self) { area in
                    chip(area.title, selected: draft.pain[area] != nil) {
                        if draft.pain[area] == nil { draft.pain[area] = 3 } else { draft.pain[area] = nil }
                    }
                }
            }
            ForEach(PainArea.allCases.filter { draft.pain[$0] != nil }, id: \.self) { area in
                Stepper(value: Binding(get: { draft.pain[area] ?? 1 }, set: { draft.pain[area] = $0 }), in: 1...10) {
                    Text("\(area.title): \(draft.pain[area] ?? 1)/10").formaStyle(.subheadline).foregroundStyle(FormaColor.ink2)
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selected ? FormaColor.onVolt : FormaColor.ink)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(selected ? FormaColor.volt : FormaColor.well, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
