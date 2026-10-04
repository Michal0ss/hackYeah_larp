import SwiftUI
import Contracts
import DesignSystem
import Onboarding

/// What the app knows about you, what stays on the phone, and how to delete it.
struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(CloudSync.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var showLogin = false
    @State private var confirmDeleteAccount = false
    @State private var confirmHealth = false
    @State private var confirmAll = false
    @State private var rebuilding = false
    @State private var rebuildFailed = false
    @State private var liveLaunch: LiveSetLaunch?

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: FormaSpacing.l) {
                    header
                    accountCard
                    planCard
                    liveTestCard
                    healthCard
                    dataCard
                    Text("hackGYM nie jest poradą medyczną. Nie stawiamy diagnoz: wskazujemy sygnały i sugerujemy rozmowę ze specjalistą.")
                        .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                }
                .padding(.horizontal, FormaSpacing.screen)
                .padding(.top, FormaSpacing.l)
                .padding(.bottom, FormaSpacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showLogin) { LoginView(showsClose: true) }
        .confirmationDialog("Usunąć konto?", isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
            Button("Usuń konto z chmury", role: .destructive) { Task { _ = await account.deleteAccount(using: store.services.api) } }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text("Zostanie usunięte konto, imię i nazwisko oraz plan zapisane w chmurze. Dane na tym telefonie zostają, a aplikacja działa dalej bez konta.")
        }
        .fullScreenCover(item: $liveLaunch) { launch in
            LiveSetFlow(exercise: launch.exercise, spec: launch.spec, totalSets: launch.sets) { liveLaunch = nil }
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
            Text("Profil, plan, historia zdrowia, check-iny, wyniki serii, rozmowa z trenerem i zgoda na dane zdrowotne znikną z tego telefonu.")
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

    private var accountCard: some View {
        card {
            SectionLabel("Konto")
            if let user = account.user, account.isSignedIn {
                Text(user.displayName).formaStyle(.headline).foregroundStyle(FormaColor.ink)
                if let email = user.email, email != user.displayName {
                    Text(email).formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                }
                syncStatus
                Text("Wylogowanie nie usuwa danych z tego telefonu.")
                    .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                Button { Task { await account.signOut() } } label: {
                    Label("Wyloguj", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity)
                }
                .buttonStyle(.formaGlass)
                Button(role: .destructive) { confirmDeleteAccount = true } label: {
                    Label(account.isDeleting ? "Usuwam konto…" : "Usuń konto", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.formaGlass)
                .disabled(account.isDeleting)
                if let message = account.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .formaStyle(.footnote).foregroundStyle(FormaColor.emberText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Nie jesteś zalogowany. Konto pozwoli przenieść plan na inny telefon.")
                    .formaStyle(.body).foregroundStyle(FormaColor.ink2)
                Button { showLogin = true } label: {
                    Label("Zaloguj się", systemImage: "person.crop.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.formaGlass)
            }
        }
    }

    /// What the account keeps, when it was last synced, and a button to do it now.
    private var syncStatus: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.s) {
            Text("W koncie: plan, odpowiedzi z onboardingu (bez zdrowia), historia treningów, wyniki techniki i cel kroków. Na telefonie zostają: wideo, rozmowy z trenerem, dane z Apple Health, check-iny i feedback po treningu.")
                .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
            Group {
                switch sync.state {
                case .syncing:
                    Label("Synchronizuję…", systemImage: "arrow.triangle.2.circlepath")
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(FormaColor.moderateText)
                case .idle:
                    if let last = sync.lastSyncedAt {
                        Label("Ostatnia synchronizacja: \(last.formatted(.relative(presentation: .named).locale(Locale(identifier: "pl_PL"))))",
                              systemImage: "checkmark.icloud")
                    } else {
                        Label("Jeszcze nie synchronizowano", systemImage: "icloud")
                    }
                }
            }
            .formaStyle(.footnote)
            .foregroundStyle(FormaColor.ink2)
            Button { Task { await sync.syncNow() } } label: {
                Label("Synchronizuj teraz", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
            }
            .buttonStyle(.formaGlass)
            .disabled(sync.state == .syncing)
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

    /// Starts the live coach on any supported exercise without going through the plan, for testing on a phone.
    private var liveTestCard: some View {
        card {
            SectionLabel("Test analizy na żywo")
            Text("Uruchom trenera na żywo od razu, bez planu. Na telefonie: prawdziwa kamera i szkielet na obrazie, ikona biedronki pokazuje liczby.")
                .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            ForEach(["squat", "pushup", "pullup"], id: \.self) { id in
                if let exercise = store.exercise(id: id) {
                    Button { startLive(exercise) } label: {
                        Label(exercise.name, systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.formaGlass)
                }
            }
        }
    }

    private func startLive(_ exercise: ExerciseItem) {
        let tempo = exercise.defaultTempo ?? TempoSpec(eccentric: 3, bottomPause: 1, concentric: 2)
        liveLaunch = LiveSetLaunch(exercise: exercise, spec: tempo, sets: 1)
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
