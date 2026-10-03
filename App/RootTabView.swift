import SwiftUI
import DesignSystem

struct RootTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            TodayView()
                .tabItem { Label("Dziś", systemImage: "bolt.fill") }
                .tag(AppTab.today)
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(AppTab.plan)
            AnalysisView()
                .tabItem { Label("Analiza", systemImage: "figure.strengthtraining.traditional") }
                .tag(AppTab.analysis)
            CoachView()
                .tabItem { Label("Trener", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(AppTab.coach)
            ProgressScreen()
                .tabItem { Label("Postępy", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.progress)
        }
    }
}
