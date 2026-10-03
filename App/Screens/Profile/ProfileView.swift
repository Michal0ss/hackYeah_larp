import SwiftUI
import Contracts
import DesignSystem
import Onboarding

/// What the app knows about you, what stays on the phone, and how to delete it.
struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmHealth = false
    @State private var confirmAll = false
    @State private var rebuilding = false
    @State private var rebuildFailed = false

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: FormaSpacing.l) {
                    header
                    planCard
                    healthCard
                    dataCard
                    Text("Forma nie jest poradą medyczną. Nie stawiamy diagnoz: wskazujemy sygnały i sugerujemy rozmowę ze specjalistą.")
                        .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                }
                .padding(.horizontal, FormaSpacing.screen)
                .padding(.top, FormaSpacing.l)
                .padding(.bottom, FormaSpacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .confirmationDialog("Usunąć historię zdrowia z telefonu?", isPresented: $confirmHealth, titleVisibility: .visible) {
            Button("Usuń historię zdrowia", role: .destructive) { store.deleteHealthHistory() }
        } message: {
            Text("Plan zostanie, ale przestanie pomijać ćwiczenia wynikające z tej historii. Możesz go potem ułożyć od nowa.")
        }
        .confirmationDialog("Usunąć wszystkie dane z telefonu?", isPresented: $confirmAll, titleVisibility: .visible) {
            Button("Usuń wszystko i zacznij od nowa", role: .destructive) {
                Task { await store.deleteAllData(); dismiss() }
            }
        } message: {
            Text("Profil, plan, historia zdrowia, check-iny i wyniki serii znikną z tego telefonu.")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: FormaSpacing.s) {
                Text("Twoje dane").formaStyle(.caption).foregroundStyle(FormaColor.ink3)
                Text("Profil").formaStyle(.largeTitle).foregroundStyle(FormaColor.ink)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                    .frame(width: 44, height: 44).background(FormaColor.well, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(FormaColor.ink)
            .accessibilityLabel("Zamknij")
        }
    }

    private var planCard: some View {
        let p = store.profile
        return card {
            SectionLabel("Cel i plan")
            line("Cel", Self.goal(p.goal))
            line("Poziom", p.level == .beginner ? "Początkujący" : "Średni")
            line("Treningi", "\(p.daysPerWeek) dni w tygodniu, ok. \(p.sessionMinutes) min")
            line("Sprzęt", Self.equipment(p.equipment))
            if !p.avoidTags.isEmpty {
                line("Pomijamy", p.avoidTags.map(\.displayName).joined(separator: ", "))
            }
            Button {
                rebuilding = true; rebuildFailed = false
                Task { rebuildFailed = !(await store.rebuildPlan()); rebuilding = false }
            } label: {
                Label(rebuilding ? "Układam plan…" : "Ułóż plan od nowa", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.formaGlass)
            .disabled(rebuilding)
            if rebuildFailed {
                Text("Nie udało się ułożyć planu. Spróbuj ponownie.").formaStyle(.footnote).foregroundStyle(FormaColor.emberText)
            }
        }
    }

    private var healthCard: some View {
        let h = store.healthHistory
        return card {
            SectionLabel("Historia zdrowia")
            Label("Zostaje na telefonie. Trener AI dostaje tylko listę ćwiczeń do pominięcia.", systemImage: "lock.fill")
                .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            if h.isEmpty {
                Text("Nic nie podano.").formaStyle(.body).foregroundStyle(FormaColor.ink2)
            } else {
                line("Kontuzje", h.injurySummary)
                line("Choroby i stany", h.conditionSummary)
            }
            if !h.isEmpty {
                Button(role: .destructive) { confirmHealth = true } label: {
                    Label("Usuń historię zdrowia", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.formaGlass)
            }
        }
    }

    private var dataCard: some View {
        card {
            SectionLabel("Moje dane")
            Text("Wideo nigdy nie opuszcza telefonu. Wszystkie dane możesz usunąć w każdej chwili.")
                .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            Button(role: .destructive) { confirmAll = true } label: {
                Label("Usuń wszystkie dane z telefonu", systemImage: "trash").frame(maxWidth: .infinity)
            }
            .buttonStyle(.formaGlass)
        }
    }

    // MARK: pieces

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m, content: content)
            .padding(FormaSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
    }

    private func line(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).formaStyle(.body).foregroundStyle(FormaColor.ink3)
            Spacer(minLength: FormaSpacing.m)
            Text(value).formaStyle(.body).foregroundStyle(FormaColor.ink).multilineTextAlignment(.trailing)
        }
    }

    private static func goal(_ g: TrainingGoal) -> String {
        switch g {
        case .strength: return "Siła"
        case .physique: return "Sylwetka"
        case .fitness: return "Kondycja"
        case .returnToMovement: return "Powrót do ruchu"
        }
    }

    private static func equipment(_ e: Equipment) -> String {
        switch e {
        case .none: return "Bez sprzętu"
        case .dumbbells: return "Hantle"
        case .gym: return "Siłownia"
        }
    }
}
