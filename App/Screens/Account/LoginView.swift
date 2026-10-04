import SwiftUI
import AuthenticationServices
import DesignSystem

/// Sign in or create an account with Google, or continue without one. Shown before onboarding on the first launch, and
/// as a sheet from "Profil" later. An account is optional: it lets the plan and the answers follow the person to
/// another phone, nothing else depends on it.
struct LoginView: View {
    /// True when shown as a sheet from Profil: adds a close button and closes itself after signing in.
    var showsClose = false

    @Environment(AccountStore.self) private var account
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.dismiss) private var dismiss
    @State private var accepted = false
    /// The button was tapped before the consent was ticked.
    @State private var consentMissing = false

    var body: some View {
        ZStack {
            AmbientBackground()
            VerticalScrollView {
                VStack(alignment: .leading, spacing: FormaSpacing.l) {
                    if showsClose { closeButton }
                    header
                    savedCard
                    stayCard
                    consent
                    if consentMissing {
                        Label("Zaznacz zgodę powyżej, żeby kontynuować.", systemImage: "exclamationmark.circle.fill")
                            .formaStyle(.subheadline)
                            .foregroundStyle(FormaColor.moderateText)
                            .accessibilityElement(children: .combine)
                    }
                    if let message = account.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .formaStyle(.subheadline)
                            .foregroundStyle(FormaColor.emberText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityElement(children: .combine)
                    }
                    actions
                }
                .padding(.horizontal, FormaSpacing.screen)
                .padding(.top, showsClose ? FormaSpacing.l : 56)
                .padding(.bottom, FormaSpacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: Pieces

    private var closeButton: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(FormaColor.ink)
                    .frame(width: 44, height: 44)
                    .glassCapsule(interactive: true)
            }
            .accessibilityLabel("Zamknij")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.s) {
            Text("Konto").formaStyle(.caption).foregroundStyle(FormaColor.ink3)
            Text("Twój plan na każdym telefonie")
                .formaStyle(.largeTitle)
                .foregroundStyle(FormaColor.ink)
                .accessibilityAddTraits(.isHeader)
            Text("Zaloguj się przez Google. Konto jest opcjonalne: bez niego wszystko działa, ale plan zostaje na tym telefonie.")
                .formaStyle(.callout)
                .foregroundStyle(FormaColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var savedCard: some View {
        card {
            SectionLabel("Na koncie zapiszemy")
            infoRow("envelope.fill", "E-mail, imię i nazwisko z konta Google")
            infoRow("calendar", "Twój plan treningowy")
            infoRow("slider.horizontal.3", "Odpowiedzi z onboardingu o celu, poziomie i sprzęcie")
        }
    }

    private var stayCard: some View {
        card {
            SectionLabel("Zostaje tylko na telefonie")
            infoRow("cross.case.fill", "Kontuzje i historia zdrowia z onboardingu")
            infoRow("heart.fill", "Dane z Apple Health: sen, tętno, kroki")
            infoRow("video.slash.fill", "Wideo i analiza techniki")
        }
    }

    private var consent: some View {
        Button { accepted.toggle(); if accepted { consentMissing = false } } label: {
            HStack(alignment: .top, spacing: FormaSpacing.m) {
                Image(systemName: accepted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24))
                    .foregroundStyle(accepted ? FormaColor.voltText : FormaColor.ink3)
                Text("Zgadzam się na zapisanie powyższych danych na moim koncie.")
                    .formaStyle(.subheadline)
                    .foregroundStyle(FormaColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(accepted ? "zaznaczone" : "niezaznaczone")
    }

    private var actions: some View {
        VStack(spacing: FormaSpacing.m) {
            Button(action: signIn) {
                HStack(spacing: FormaSpacing.s) {
                    if account.isSigningIn {
                        ProgressView().tint(FormaColor.onVolt)
                    } else {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                    }
                    Text(account.isSigningIn ? "Łączę z Google…" : "Kontynuuj z Google")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.formaPrimary)
            .disabled(account.isSigningIn)

            if !showsClose {
                Button { account.skip() } label: {
                    Text("Kontynuuj bez konta").frame(maxWidth: .infinity)
                }
                .buttonStyle(.formaGlass)
                .disabled(account.isSigningIn)
            }
        }
    }

    private func signIn() {
        guard accepted else {
            consentMissing = true
            return
        }
        let acceptedAt = Date()
        Task {
            await account.signInWithGoogle(acceptedAt: acceptedAt) { url in
                try await webAuthenticationSession.authenticate(
                    using: url, callbackURLScheme: AccountConfig.current.callbackScheme)
            }
            if account.isSignedIn, showsClose { dismiss() }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m, content: content)
            .padding(FormaSpacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
    }

    private func infoRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: FormaSpacing.m) {
            Image(systemName: symbol)
                .foregroundStyle(FormaColor.voltText)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .formaStyle(.subheadline)
                .foregroundStyle(FormaColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
