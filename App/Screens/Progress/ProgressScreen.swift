import SwiftUI
import Contracts
import DesignSystem
import Insights

/// "Postępy": technique score over time, weight progress of the most-logged exercise, recovery and mood
/// over time, recent sets, and the way to care.
/// Owner: Wiktor.
struct ProgressScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var model = ProgressModel()
    @State private var showCare = false
    @State private var showCheckIn = false

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: FormaSpacing.l) {
                    header
                    if !model.loaded {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, FormaSpacing.xxl)
                    } else if model.isFullyEmpty {
                        EmptyProgressCard(onAnalyse: { router.tab = .analysis }, onCheckIn: { showCheckIn = true })
                    } else {
                        if let care = model.care {
                            CareTeaserCard(assessment: care, simulated: model.isMixed && model.careSimulated) { showCare = true }
                        }
                        TechniqueCard(progress: model.report.technique, simulated: model.isMixed && model.techniqueSimulated,
                                      onAnalyse: { router.tab = .analysis })
                        if let strength = model.report.strength {
                            StrengthCard(progress: strength)
                        }
                        RecoveryMoodCard(report: model.report,
                                         simulated: model.isMixed && (model.recoverySimulated || model.moodSimulated),
                                         onCheckIn: { showCheckIn = true })
                        if !model.recentSets.isEmpty {
                            RecentSetsCard(sets: model.recentSets)
                        }
                        footer
                    }
                }
                .padding(.horizontal, FormaSpacing.screen)
                .padding(.top, FormaSpacing.l)
                .padding(.bottom, FormaSpacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .task { await model.load(services: store.services) }
        .sheet(isPresented: $showCare) {
            if let care = model.care {
                CareView(assessment: care, simulated: model.careSimulated)
            }
        }
        .sheet(isPresented: $showCheckIn, onDismiss: { Task { await model.load(services: store.services) } }) {
            CheckInView()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.s) {
            Text("Ostatnie 14 dni")
                .formaStyle(.caption)
                .foregroundStyle(FormaColor.ink3)
            Text("Postępy")
                .formaStyle(.largeTitle)
                .foregroundStyle(FormaColor.ink)
            if model.showsHeaderBadge {
                SimulatedBadge()
            }
        }
    }

    private var footer: some View {
        return Text(model.anySimulated ? "Wykresy pokazują dane przykładowe (symulacja). To nie jest porada medyczna."
                              : "To nie jest porada medyczna.")
            .formaStyle(.footnote)
            .foregroundStyle(FormaColor.ink3)
            .padding(.top, FormaSpacing.xs)
    }
}
