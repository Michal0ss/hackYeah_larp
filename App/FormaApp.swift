import SwiftUI
import Contracts
import DesignSystem
import Content

@main
struct FormaApp: App {
    @State private var store: AppStore
    @State private var router = AppRouter()
    @State private var account: AccountStore
    @State private var sync: CloudSync
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = AppStore()
        let account = AccountStore()
        _store = State(initialValue: store)
        _account = State(initialValue: account)
        _sync = State(initialValue: CloudSync(store: store, account: account))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .environment(account)
                .environment(sync)
                // Dark is the default look. A settings switch can come later.
                .preferredColorScheme(.dark)
                .tint(FormaColor.voltText)
                // Newer catalog and thresholds from the backend; offline we keep the bundled or cached copy.
                .task {
                    await account.restore()
                    // Deletions here reach the account at once; new data is sent soon after it appears.
                    store.onCloudDelete = { deletion in Task { await sync.forget(deletion) } }
                    store.onDataChanged = { Task { await sync.push() } }
                }
                // Signed in on this phone (now or earlier): send what it has and take what the account has.
                .task(id: account.user?.id) {
                    guard account.isSignedIn, store.onboardingCompleted else { return }
                    await sync.syncNow()
                }
                // A changed plan goes to the account (the pause between runs keeps it from running on every edit).
                .onChange(of: store.plan) { _, _ in Task { await sync.push() } }
                .task {
                    await store.loadSavedCheckIn()
                    await store.refreshHealth()  // also recomputes the recommendation
                    if await ContentRepository.shared.refresh(using: store.services.api) { await store.contentDidUpdate() }
                }
                // New sleep or heart rate may have arrived while the app was in the background.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, store.onboardingCompleted { Task { await store.refreshHealth() } }
                    // Leaving the app: the last chance to send what changed since the last run.
                    if phase == .background { Task { await sync.push(force: true) } }
                }
        }
    }
}

/// Sign-in choice and onboarding on the first launch, then the tab bar.
struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(AccountStore.self) private var account
    @Environment(CloudSync.self) private var sync

    var body: some View {
        ZStack {
            if store.onboardingCompleted {
                RootTabView()
                    .transition(.opacity)
            } else if account.needsChoice {
                LoginView()
                    .transition(.opacity)
            } else {
                OnboardingFlow(services: store.services) { result in
                    withAnimation(.easeInOut(duration: 0.5)) { store.completeOnboarding(result) }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: account.needsChoice)
        // A new phone, signed in to an account that already has a plan: start from it instead of onboarding.
        .task(id: account.user?.id) {
            guard account.isSignedIn, !store.onboardingCompleted, let setup = await sync.fetchSetup() else { return }
            withAnimation(.easeInOut(duration: 0.5)) { store.restoreFromAccount(setup) }
            await sync.pull()
        }
        .overlay {
            if sync.state == .syncing, !store.onboardingCompleted { RestoringOverlay() }
        }
    }
}

/// Shown for a moment while the plan and the history are fetched from the account on a new phone.
private struct RestoringOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: FormaSpacing.m) {
                ProgressView().tint(FormaColor.volt)
                Text("Przywracam plan i historię z konta…").formaStyle(.callout).foregroundStyle(FormaColor.ink)
            }
            .padding(FormaSpacing.xl)
            .glassCard()
        }
        .accessibilityElement(children: .combine)
    }
}
