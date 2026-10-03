import SwiftUI
import Contracts
import DesignSystem
import Insights
import Onboarding

/// "Dziś": the recommendation of the day, today's session and the recovery strip.
/// Owner: Michał.
struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var showCheckIn = false
    @State private var liveLaunch: LiveSetLaunch?
    @State private var showProfile = false

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: FormaSpacing.l) {
                    header
                    RecommendationCard(recommendation: store.recommendation)
                    if let entry = store.todaySession {
                        let adjustment = store.adjustment(for: entry.session)
                        SessionCard(adjustment: adjustment, isToday: entry.isToday,
                                    restored: store.isRestored(entry.session),
                                    onStart: { startSet(in: adjustment.session) },
                                    onToggle: { store.toggleOriginal(entry.session) })
                    }
                    RecoveryStrip(today: store.today, checkIn: store.checkIn)
                    actions
                }
                .padding(.horizontal, FormaSpacing.screen)
                .padding(.top, FormaSpacing.l)
                .padding(.bottom, FormaSpacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showCheckIn) {
            CheckInView()
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
        }
        .fullScreenCover(item: $liveLaunch) { launch in
            LiveSetFlow(exercise: launch.exercise, spec: launch.spec, totalSets: launch.sets) {
                liveLaunch = nil
            }
        }
    }

    /// Starts the live coach for the first exercise of the session that has a target tempo.
    private func startSet(in session: PlannedSession) {
        guard let planned = session.exercises.first(where: { $0.tempo != nil }),
              let tempo = planned.tempo,
              let exercise = store.exercise(id: planned.exerciseId) else { return }
        // The session is already adjusted (PlanAdjuster), so its sets are the ones to do.
        liveLaunch = LiveSetLaunch(exercise: exercise, spec: tempo, sets: planned.sets)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.s) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                .formaStyle(.caption)
                .foregroundStyle(FormaColor.ink3)
            HStack {
                Text("Dziś")
                    .formaStyle(.largeTitle)
                    .foregroundStyle(FormaColor.ink)
                Spacer()
                Button { showProfile = true } label: {
                    Image(systemName: "person.crop.circle").font(.system(size: 26))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(FormaColor.ink2)
                .accessibilityLabel("Profil i dane")
            }
            if store.recommendation.isSimulated {
                SimulatedBadge()
            }
        }
    }

    private var actions: some View {
        HStack(spacing: FormaSpacing.m) {
            Button {
                showCheckIn = true
            } label: {
                Label("Check-in", systemImage: "face.smiling")
            }
            .buttonStyle(.formaGlass)

            Button {
                router.tab = .coach
            } label: {
                Label("Zapytaj trenera", systemImage: "bubble.left.fill")
            }
            .buttonStyle(.formaPrimary)
        }
    }
}

private struct RecommendationCard: View {
    let recommendation: DailyRecommendation
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            HStack {
                SectionLabel("Rekomendacja dnia")
                Spacer()
                DecisionChip(recommendation.decision)
            }
            Text(recommendation.headline)
                .formaStyle(.title)
                .foregroundStyle(FormaColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(recommendation.suggestedAction)
                .formaStyle(.body)
                .foregroundStyle(FormaColor.ink2)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("Dlaczego?")
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FormaColor.voltText)
                .frame(minHeight: 44)
            }
            .accessibilityHint("Pokazuje czynniki rekomendacji")

            if expanded {
                VStack(alignment: .leading, spacing: FormaSpacing.s) {
                    ForEach(recommendation.factors) { factor in
                        HStack(alignment: .top, spacing: FormaSpacing.s) {
                            Image(systemName: factor.isNegative ? "arrow.down.right.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(factor.isNegative ? FormaColor.moderateText : FormaColor.goText)
                            Text(factor.text)
                                .formaStyle(.subheadline)
                                .foregroundStyle(FormaColor.ink2)
                        }
                    }
                    Text("To sygnały, nie porada medyczna.")
                        .formaStyle(.footnote)
                        .foregroundStyle(FormaColor.ink3)
                        .padding(.top, 2)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(FormaSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

struct LiveSetLaunch: Identifiable {
    let id = UUID()
    let exercise: ExerciseItem
    let spec: TempoSpec
    let sets: Int
}

private struct SessionCard: View {
    @Environment(AppStore.self) private var store
    let adjustment: PlanAdjustment
    let isToday: Bool
    let restored: Bool
    let onStart: () -> Void
    let onToggle: () -> Void

    private var session: PlannedSession { adjustment.session }
    private var adapted: Bool { adjustment.isChanged }

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            HStack {
                SectionLabel(isToday ? "Dzisiejsza sesja" : "Najbliższa sesja")
                Spacer()
                if adapted {
                    Label("Zmieniona", systemImage: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FormaColor.moderateText)
                }
            }
            Text(session.title)
                .formaStyle(.title2)
                .foregroundStyle(FormaColor.ink)

            VStack(spacing: 0) {
                ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        Text(store.exercise(id: item.exerciseId)?.name ?? item.exerciseId)
                            .formaStyle(.body)
                            .foregroundStyle(FormaColor.ink)
                        Spacer()
                        Text("\(item.sets) × \(item.repsMin)–\(item.repsMax)")
                            .font(.formaNumber(15))
                            .monospacedDigit()
                            .foregroundStyle(FormaColor.ink2)
                    }
                    .padding(.vertical, 10)
                    if index < session.exercises.count - 1 {
                        Divider().overlay(FormaColor.line)
                    }
                }
            }

            AdjustmentNote(adjustment: adjustment, restored: restored, onToggle: onToggle)

            if session.exercises.contains(where: { $0.tempo != nil }) {
                Button(action: onStart) {
                    Label("Zacznij serię z trenerem", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.formaPrimary)
                .padding(.top, FormaSpacing.xs)
            }
        }
        .padding(FormaSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

private struct RecoveryStrip: View {
    let today: RecoverySnapshot?
    let checkIn: CheckIn?

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            SectionLabel("Regeneracja")
            HStack(alignment: .top, spacing: FormaSpacing.m) {
                stat("Sen", sleepText, unit: nil)
                stat("Tętno spocz.", today.map { "\($0.restingHeartRate)" } ?? "–", unit: "bpm")
                stat("HRV", today.map { "\($0.hrvMs)" } ?? "–", unit: "ms")
                stat("Nastrój", checkIn.map { "\($0.mood)/5" } ?? "–", unit: nil)
            }
        }
        .padding(FormaSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var sleepText: String {
        guard let minutes = today?.sleepMinutes else { return "–" }
        return "\(minutes / 60) h \(minutes % 60)"
    }

    private func stat(_ label: String, _ value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NumberText(value, size: 20, unit: unit)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .formaStyle(.footnote)
                .foregroundStyle(FormaColor.ink3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    TodayView()
        .environment(AppStore(onboardingStorage: InMemoryOnboardingStorage()))
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}
