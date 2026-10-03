import SwiftUI
import Contracts
import DesignSystem

@main
struct FormaApp: App {
    @State private var store = AppStore()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                // Dark is the default look. A settings switch can come later.
                .preferredColorScheme(.dark)
                .tint(FormaColor.voltText)
        }
    }
}

/// Onboarding on the first launch, then the tab bar.
struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ZStack {
            if store.onboardingCompleted {
                RootTabView()
                    .transition(.opacity)
            } else {
                OnboardingFlow(services: store.services) { result in
                    withAnimation(.easeInOut(duration: 0.5)) { store.completeOnboarding(result) }
                }
                .transition(.opacity)
            }
        }
    }
}
