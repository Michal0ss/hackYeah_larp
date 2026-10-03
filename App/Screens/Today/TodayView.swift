import SwiftUI
import Contracts
import Health
import DesignSystem
import Insights
import LiveSet
import Onboarding

/// "Dziś": the recommendation of the day, today's session and the recovery strip.
/// Owner: Michał.
struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var showCheckIn = false
    @State private var liveLaunch: LiveSetLaunch?
    @State private var showProfile = false
    @State private var showCare = false
    /// Same data and rules as the Postępy tab, to show the care signal here too.
    @State private var careModel = ProgressModel()

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: FormaSpacing.l) {
                    header
                    RecommendationCard(recommendation: store.recommendation, text: store.recommendationText)
                    if let care = careModel.care {
                        CareTeaserCard(assessment: care, simulated: careModel.careSimulated) { showCare = true }
                    }
                    if let entry = store.todaySession {
                        let adjustment = store.adjustment(for: entry.session)
                        SessionCard(adjustment: adjustment, isToday: entry.isToday,
                                    restored: store.isRestored(entry.session),
                                    onStart: { startSet(in: adjustment.session) },
                                    onToggle: { store.toggleOriginal(entry.session) })
                    }
                    RecoveryStrip(health: store.health, loaded: store.healthLoaded,
                                  accessGranted: store.healthAccess == .granted, checkIn: store.checkIn)
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
        .sheet(isPresented: $showCare) {
            if let care = careModel.care { CareView(assessment: care, simulated: careModel.careSimulated) }
        }
        .task(id: store.recommendation) { await careModel.load(services: store.services) }
        .fullScreenCover(item: $liveLaunch) { launch in
            LiveSetFlow(exercise: launch.exercise, spec: launch.spec, totalSets: launch.sets) {
                liveLaunch = nil
            }
        }
    }

    /// Starts the live coach for the first exercise of the session that has a target tempo.
    private func startSet(in session: PlannedSession) {
        guard let planned = session.exercises.first(where: { item in
                  item.tempo != nil && store.exercise(id: item.exerciseId).flatMap(MovementKind.kind(for:)) != nil }),
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
    let text: RecommendationText
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            HStack {
                SectionLabel("Rekomendacja dnia")
                Spacer()
                DecisionChip(recommendation.decision)
            }
            Text(text.headline)
                .formaStyle(.title)
                .foregroundStyle(FormaColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(text.explanation)
                .formaStyle(.body)
                .foregroundStyle(FormaColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if text.source == .ai {
                Label("Sformułowane przez trenera AI. Decyzję liczą reguły w aplikacji.", systemImage: "sparkles")
                    .formaStyle(.footnote)
                    .foregroundStyle(FormaColor.ink3)
            }

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

            if session.exercises.contains(where: { item in
                item.tempo != nil && store.exercise(id: item.exerciseId).flatMap(MovementKind.kind(for:)) != nil }) {
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

/// Sleep, resting heart rate and HRV from Apple Health (or flagged sample data), next to today's mood.
private struct RecoveryStrip: View {
    let health: HealthDaySummary?
    /// False until the first read finished (then the numbers are placeholders, not "missing").
    let loaded: Bool
    /// The user allowed Apple Health: no numbers then mean "Health has nothing for you yet".
    let accessGranted: Bool
    let checkIn: CheckIn?

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Regeneracja")
                Spacer()
                source
            }
            HStack(alignment: .top, spacing: FormaSpacing.m) {
                stat("Sen", sleepText, unit: nil, note: nil, spoken: nil)
                stat("Tętno spocz.", health?.restingHeartRate.map { "\($0)" } ?? "–", unit: "bpm",
                     note: health?.restingHeartRateDelta.map(signed),
                     spoken: health?.restingHeartRateDelta.map { "\(abs($0)) uderzeń \($0 < 0 ? "poniżej" : "powyżej") średniej" })
                stat("HRV", health?.hrvMs.map { "\($0)" } ?? "–", unit: "ms",
                     note: health?.hrvDeltaPercent.map { signed($0) + "%" },
                     spoken: health?.hrvDeltaPercent.map { "\(abs($0)) procent \($0 < 0 ? "poniżej" : "powyżej") średniej" })
                stat("Nastrój", checkIn.map { "\($0.mood)/5" } ?? "–", unit: nil, note: nil, spoken: nil)
            }
            if let hint {
                Text(hint)
                    .formaStyle(.footnote)
                    .foregroundStyle(FormaColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(FormaSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private var source: some View {
        if let health {
            if health.isSimulated {
                SimulatedBadge()
            } else {
                Label("Apple Health · \(dayLabel(health.date))", systemImage: "heart.fill")
                    .labelStyle(.titleAndIcon)
                    .formaStyle(.footnote)
                    .foregroundStyle(FormaColor.ink3)
            }
        }
    }

    private var sleepText: String {
        guard let minutes = health?.sleepMinutes else { return "–" }
        return "\(minutes / 60) h \(minutes % 60)"
    }

    /// What is missing and why, only when it matters.
    private var hint: String? {
        guard loaded else { return nil }
        guard let health else {
            return accessGranted
                ? "Brak danych w Apple Health. Sen, tętno i HRV zapisuje zwykle zegarek. Sprawdź dostęp w Ustawieniach: Zdrowie, Dostęp do danych i urządzenia."
                : nil
        }
        if !health.isSimulated, health.restingHeartRate == nil && health.hrvMs == nil {
            return "Brak tętna spoczynkowego i HRV. Zwykle mierzy je zegarek."
        }
        return nil
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "dziś" }
        if calendar.isDateInYesterday(date) { return "wczoraj" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    private func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : value < 0 ? "−\(abs(value))" : "0" }

    private func stat(_ label: String, _ value: String, unit: String?, note: String?, spoken: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NumberText(value, size: 20, unit: unit)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .formaStyle(.footnote)
                .foregroundStyle(FormaColor.ink3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let note {
                Text(note + " od średniej")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FormaColor.ink3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue([value, unit, spoken].compactMap { $0 }.joined(separator: " "))
    }
}

#Preview {
    TodayView()
        .environment(AppStore(onboardingStorage: InMemoryOnboardingStorage()))
        .environment(AppRouter())
        .preferredColorScheme(.dark)
}
