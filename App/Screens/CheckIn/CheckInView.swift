import SwiftUI
import Contracts
import DesignSystem

/// 15-second check-in: mood, stress, energy (1...5). Owner: Michał.
struct CheckInView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var mood = 3
    @State private var stress = 3
    @State private var energy = 3
    @State private var note = ""

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: FormaSpacing.l) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionLabel("Check-in")
                            Text("Jak się dziś czujesz?")
                                .formaStyle(.title)
                                .foregroundStyle(FormaColor.ink)
                        }
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(FormaColor.ink)
                                .frame(width: 44, height: 44)
                                .glassCapsule(interactive: true)
                        }
                        .accessibilityLabel("Zamknij")
                    }

                    VStack(alignment: .leading, spacing: FormaSpacing.xl) {
                        ScalePicker(title: "Nastrój", lowLabel: "Niski", highLabel: "Świetny", value: $mood)
                        ScalePicker(title: "Stres", lowLabel: "Spokój", highLabel: "Duży stres", value: $stress)
                        ScalePicker(title: "Energia", lowLabel: "Brak sił", highLabel: "Pełno energii", value: $energy)
                    }
                    .padding(FormaSpacing.xl)
                    .glassCard()

                    VStack(alignment: .leading, spacing: FormaSpacing.s) {
                        SectionLabel("Notatka (opcjonalnie)")
                        TextField("Np. kolano trochę ciągnie", text: $note, axis: .vertical)
                            .lineLimit(2...4)
                            .foregroundStyle(FormaColor.ink)
                    }
                    .padding(FormaSpacing.xl)
                    .glassCard()

                    Text("To skala samopoczucia, nie ocena medyczna.")
                        .formaStyle(.footnote)
                        .foregroundStyle(FormaColor.ink3)

                    Button {
                        store.checkIn = CheckIn(date: Date(), mood: mood, stress: stress, energy: energy,
                                                note: note.isEmpty ? nil : note)
                        dismiss()
                    } label: {
                        Text("Zapisz")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.formaPrimary)
                }
                .padding(.horizontal, FormaSpacing.screen)
                .padding(.top, FormaSpacing.xl)
                .padding(.bottom, FormaSpacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            if let current = store.checkIn {
                mood = current.mood
                stress = current.stress
                energy = current.energy
            }
        }
    }
}

#Preview {
    CheckInView()
        .environment(AppStore())
        .preferredColorScheme(.dark)
}
