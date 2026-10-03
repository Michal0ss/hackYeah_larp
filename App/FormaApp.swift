import SwiftUI
import Contracts
import DesignSystem

@main
struct FormaApp: App {
    @State private var store = AppStore()
    @State private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(store)
                .environment(router)
                // Dark is the default look. A settings switch can come later.
                .preferredColorScheme(.dark)
                .tint(FormaColor.voltText)
        }
    }
}
