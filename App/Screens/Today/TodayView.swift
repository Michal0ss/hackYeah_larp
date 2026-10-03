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
    @State private var workout: WorkoutLaunch?
    @State private var repeating: PlannedSession?
    @State private var showProfile = false
    @State private var showCare = false
    @State private var showHealthData = false
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
                                    onStart: { workout = WorkoutLaunch(session: adjustment.session) },
                                    onRepeat: { repeating = entry.session },
                                    onToggle: { store.toggleOriginal(entry.session) })
                    }
                    RecoveryStrip(health: store.health, loaded: store.healthLoaded, report: store.healthReport,
                                  accessGranted: store.healthAccess == .granted, checkIn: store.checkIn,
                                  onOpen: { showHealthData = true })
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
        .sheet(isPresented: $showHealthData) {
            HealthDataView(load: { await store.loadHealthOverview() })
        }
        .sheet(isPresented: $showCare) {
            if let care = careModel.care { CareView(assessment: care, simulated: careModel.careSimulated) }
        }
        .task(id: store.recommendation) { await careModel.load(services: store.services) }
        .confirmationDialog("Powtórzyć trening?", isPresented: Binding(get: { repeating != nil }, set: { if !$0 { repeating = nil } }),
                            titleVisibility: .visible) {
            Button("Usuń zapisane serie i zacznij od nowa", role: .destructive) {
                if let session = repeating {
                    store.resetWorkout(sessionId: session.id)
                    workout = WorkoutLaunch(session: store.adjustment(for: session).session)
                }
                repeating = nil
            }
            Button("Anuluj", role: .cancel) { repeating = nil }
        } message: {
            Text("Zapisane serie tej sesji (powtórzenia, ciężar, poprawki) zostaną usunięte, a sesja przestanie być wykonana.")
        }
        .fullScreenCover(item: $workout) { launch in
            WorkoutRunnerView(session: launch.session, startExercise: launch.startExercise) { workout = nil }
        }
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
    let onRepeat: () -> Void
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

            if session.status == .done {
                Label("Wykonana", systemImage: "checkmark.circle.fill")
                    .formaStyle(.headline).foregroundStyle(FormaColor.goText)
                    .padding(.top, FormaSpacing.xs)
                Button(action: onRepeat) {
                    Label("Powtórz trening", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.formaGlass)
            } else if session.status != .skipped {
                Button(action: onStart) {
                    Label("Zacznij trening", systemImage: "play.fill").frame(maxWidth: .infinity)
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
    /// What the last read found: the reason behind "no data".
    let report: HealthReadReport?
    /// The user allowed Apple Health: no numbers then mean "Health has nothing for you yet".
    let accessGranted: Bool
    let checkIn: CheckIn?
    /// Opens the "Dane zdrowotne" panel.
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) { card }
            .buttonStyle(.plain)
            .accessibilityHint("Otwiera panel z danymi z Apple Health")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Dane zdrowotne")
                Spacer()
                source
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FormaColor.ink3)
                    .accessibilityHidden(true)
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
            if let detail {
                Text(detail)
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
            guard accessGranted else { return nil }
            if report?.failed == true {
                return "Nie udało się odczytać Apple Health. Odblokuj telefon i otwórz aplikację ponownie."
            }
            return "Brak danych w Apple Health. Aplikacja czyta sen, tętno spoczynkowe i HRV, a dwa ostatnie zapisuje zwykle zegarek. Sprawdź dostęp w Ustawieniach: Zdrowie, Dostęp do danych i urządzenia."
        }
        if !health.isSimulated, health.restingHeartRate == nil && health.hrvMs == nil {
            return "Brak tętna spoczynkowego i HRV. Zwykle mierzy je zegarek."
        }
        return nil
    }

    /// The counts behind "no data", so a reader can tell "Health has none of these" from "the read failed".
    private var detail: String? {
        guard loaded, accessGranted, health == nil else { return nil }
        return report?.summaryText
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
