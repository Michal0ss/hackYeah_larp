import SwiftUI
import Contracts
import DesignSystem
import Insights
import LiveSet
import Onboarding

/// Week plan: a day strip, the selected session and its exercises. Built by Michał while Maciek works on the
/// generator (his `feat/maciek-plan-coach-screens` can restyle or extend it). Marking a session done is not here yet.
struct PlanView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedWeekday: Int?
    @State private var liveLaunch: LiveSetLaunch?

    private static let dayLetters = ["Pn", "Wt", "Śr", "Cz", "Pt", "So", "Nd"]

    private var sessions: [PlannedSession] { store.plan.sessions.sorted { $0.weekday < $1.weekday } }

    private var todayWeekday: Int {
        let weekday = Calendar(identifier: .iso8601).component(.weekday, from: Date())
        return weekday == 1 ? 7 : weekday - 1
    }

    /// The chosen day, otherwise today's session, otherwise the next one.
    private var selected: PlannedSession? {
        if let day = selectedWeekday, let match = sessions.first(where: { $0.weekday == day }) { return match }
        return sessions.first { $0.weekday == todayWeekday }
            ?? sessions.first { $0.weekday > todayWeekday } ?? sessions.first
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: FormaSpacing.l) {
                    header
                    weekStrip
                    if let session = selected {
                        let adjustment = store.adjustment(for: session)
                        SessionDetail(adjustment: adjustment, restored: store.isRestored(session),
                                      onToggle: { store.toggleOriginal(session) }) { start($0, in: adjustment.session) }
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, FormaSpacing.screen)
                .padding(.top, FormaSpacing.l)
                .padding(.bottom, FormaSpacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .fullScreenCover(item: $liveLaunch) { launch in
            LiveSetFlow(exercise: launch.exercise, spec: launch.spec, totalSets: launch.sets) { liveLaunch = nil }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.s) {
            Text("Twój tydzień").formaStyle(.caption).foregroundStyle(FormaColor.ink3)
            Text("Plan").formaStyle(.largeTitle).foregroundStyle(FormaColor.ink)
            Text(store.plan.source == .ai ? "Plan ułożony przez trenera AI" : "Plan z gotowego szablonu")
                .formaStyle(.subheadline).foregroundStyle(FormaColor.ink3)
            // Why the plan is a template when the AI was meant to write it (the generator's notice).
            if let notice = store.plan.notices.first {
                InfoBanner(systemImage: "info.circle.fill") {
                    Text(notice.userMessage).formaStyle(.footnote).foregroundStyle(FormaColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { day in
                let hasSession = sessions.contains { $0.weekday == day }
                let isSelected = selected?.weekday == day
                Button { selectedWeekday = day } label: {
                    VStack(spacing: 6) {
                        Text(Self.dayLetters[day - 1])
                            .font(.system(size: 13, weight: .bold))
                        Circle()
                            .fill(hasSession ? (isSelected ? FormaColor.onVolt : FormaColor.voltText) : Color.clear)
                            .frame(width: 6, height: 6)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(isSelected ? FormaColor.onVolt : (day == todayWeekday ? FormaColor.voltText : FormaColor.ink2))
                    .background(isSelected ? FormaColor.volt : FormaColor.well, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(day == todayWeekday ? FormaColor.voltText.opacity(0.5) : .clear))
                }
                .buttonStyle(.plain)
                .disabled(!hasSession)
                .accessibilityLabel("\(Self.dayLetters[day - 1])\(hasSession ? ", jest trening" : ", wolne")")
            }
        }
    }

    private var emptyState: some View {
        Text("Nie masz jeszcze planu. Ułożymy go po onboardingu.")
            .formaStyle(.body).foregroundStyle(FormaColor.ink2)
            .padding(FormaSpacing.xl).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private func start(_ planned: PlannedExercise, in session: PlannedSession) {
        guard let tempo = planned.tempo, let exercise = store.exercise(id: planned.exerciseId) else { return }
        // The session is already adjusted (PlanAdjuster), so its sets are the ones to do.
        liveLaunch = LiveSetLaunch(exercise: exercise, spec: tempo, sets: planned.sets)
    }
}

private struct SessionDetail: View {
    @Environment(AppStore.self) private var store
    let adjustment: PlanAdjustment
    let restored: Bool
    let onToggle: () -> Void
    let onStart: (PlannedExercise) -> Void

    private var session: PlannedSession { adjustment.session }
    private var adapted: Bool { adjustment.isChanged }

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            HStack {
                SectionLabel(Self.dayNames[session.weekday - 1])
                Spacer()
                if adapted {
                    Label(adjustment.isRestDay ? "Odpoczynek" : "Lżejsza dziś", systemImage: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(FormaColor.moderateText)
                }
            }
            Text(session.title).formaStyle(.title2).foregroundStyle(FormaColor.ink)

            VStack(spacing: 0) {
                ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, item in
                    row(item)
                    if index < session.exercises.count - 1 { Divider().overlay(FormaColor.line) }
                }
            }
            AdjustmentNote(adjustment: adjustment, restored: restored, onToggle: onToggle)
        }
        .padding(FormaSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func row(_ item: PlannedExercise) -> some View {
        let exercise = store.exercise(id: item.exerciseId)
        let unit = (exercise?.timed ?? false) ? " s" : ""
        return HStack(alignment: .center, spacing: FormaSpacing.m) {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise?.name ?? item.exerciseId).formaStyle(.body).foregroundStyle(FormaColor.ink)
                Text(detail(item))
                    .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            }
            Spacer()
            Text("\(item.sets) × \(item.repsMin)–\(item.repsMax)\(unit)")
                .font(.formaNumber(15)).monospacedDigit().foregroundStyle(FormaColor.ink2)
            // The live coach reads a squat signal (hip depth), so it is offered for squat-pattern exercises only.
            if let exercise, MovementKind.kind(for: exercise) != nil, item.tempo != nil {
                Button { onStart(item) } label: {
                    Image(systemName: "play.fill").font(.system(size: 14, weight: .bold))
                        .frame(width: 38, height: 38)
                        .foregroundStyle(FormaColor.onVolt)
                        .background(FormaColor.volt, in: Circle())
                }
                .accessibilityLabel("Zacznij serię z trenerem")
            }
        }
        .padding(.vertical, 10)
    }

    private func detail(_ item: PlannedExercise) -> String {
        var parts = ["przerwa \(item.restSeconds) s"]
        if let t = item.tempo {
            func n(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }
            parts.append("tempo \(n(t.eccentric))-\(n(t.bottomPause))-\(n(t.concentric))-\(n(t.topPause))")
        }
        return parts.joined(separator: " · ")
    }

    private static let dayNames = ["Poniedziałek", "Wtorek", "Środa", "Czwartek", "Piątek", "Sobota", "Niedziela"]
}

#Preview {
    PlanView()
        .environment(AppStore(onboardingStorage: InMemoryOnboardingStorage()))
        .preferredColorScheme(.dark)
}
