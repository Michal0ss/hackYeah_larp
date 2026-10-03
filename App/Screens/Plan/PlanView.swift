import SwiftUI
import Contracts
import DesignSystem
import Insights
import LiveSet
import Onboarding

/// Plan by date: a week strip with arrows between the weeks of the plan, the selected session and its exercises.
/// Marking a session done is not here yet (session-flow).
struct PlanView: View {
    @Environment(AppStore.self) private var store
    /// The day the user tapped; nil means today's session (or the next one).
    @State private var selectedDate: Date?
    /// How many weeks the strip is moved from the week of the shown session.
    @State private var weekShift = 0
    @State private var rebuilding = false
    @State private var workout: WorkoutLaunch?
    @State private var editing: PlannedSession?
    @State private var addingSession = false
    @State private var logSession: PlannedSession?

    private static let dayLetters = ["Pn", "Wt", "Śr", "Cz", "Pt", "So", "Nd"]
    private static var calendar: Calendar { TrainingPlan.calendar }

    private var plan: TrainingPlan { store.resolvedPlan }

    /// The chosen day's session, otherwise today's, otherwise the next one.
    private var selected: PlannedSession? {
        if let day = selectedDate, let match = plan.session(on: day) { return match }
        return plan.sessionOnOrAfter(Date())
    }

    /// The day the strip is built around: the shown session, or today when the plan has run out.
    private var anchorDay: Date {
        let base = selected?.date ?? Date()
        return Self.calendar.date(byAdding: .weekOfYear, value: weekShift, to: base) ?? base
    }

    /// Monday to Sunday of the week on the strip.
    private var weekDays: [Date] {
        guard let start = Self.calendar.dateInterval(of: .weekOfYear, for: anchorDay)?.start else { return [] }
        return (0..<7).compactMap { Self.calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: FormaSpacing.l) {
                    header
                    if store.planHasEnded { endedCard }
                    weekStrip
                    if let session = selected {
                        let adjustment = store.adjustment(for: session)
                        SessionDetail(adjustment: adjustment, restored: store.isRestored(session),
                                      onToggle: { store.toggleOriginal(session) }, onEdit: { editing = session },
                                      onRestore: { store.edit(.restore, sessionId: session.id) },
                                      onStartWorkout: { workout = WorkoutLaunch(session: adjustment.session) },
                                      onShowLog: { logSession = session }) {
                            start($0, in: adjustment.session)
                        }
                        Button { addingSession = true } label: {
                            Label("Dodaj własną sesję", systemImage: "plus").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.formaGlass)
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
        .overlay(alignment: .bottom) { undoBar }
        .sheet(item: $editing) { SessionEditSheet(sessionId: $0.id) }
        .sheet(isPresented: $addingSession) { AddSessionSheet() }
        .sheet(item: $logSession) { WorkoutLogSheet(session: $0) }
        .fullScreenCover(item: $workout) { launch in
            WorkoutRunnerView(session: launch.session, startExercise: launch.startExercise) { workout = nil }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.s) {
            Text(weekTitle).formaStyle(.caption).foregroundStyle(FormaColor.ink3)
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

    /// "6–12 października", from the week on the strip.
    private var weekTitle: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "Twój plan" }
        let sameMonth = Self.calendar.component(.month, from: first) == Self.calendar.component(.month, from: last)
        let from = first.formatted(sameMonth ? .dateTime.day() : .dateTime.day().month(.abbreviated))
        return "\(from)–\(last.formatted(.dateTime.day().month(.wide)))"
    }

    private var canGoBack: Bool {
        guard let firstSession = plan.sessions.compactMap(\.date).min(), let first = weekDays.first else { return false }
        return first > Self.calendar.startOfDay(for: firstSession)
    }

    private var canGoForward: Bool {
        guard let last = plan.lastSessionDate, let end = weekDays.last else { return false }
        return end < Self.calendar.startOfDay(for: last)
    }

    private var weekStrip: some View {
        VStack(spacing: FormaSpacing.s) {
            HStack(spacing: 6) {
                Button { weekShift -= 1 } label: { Image(systemName: "chevron.left").frame(width: 24, height: 56) }
                    .disabled(!canGoBack).accessibilityLabel("Poprzedni tydzień")
                ForEach(Array(weekDays.enumerated()), id: \.offset) { index, day in dayCell(day, letter: Self.dayLetters[index]) }
                Button { weekShift += 1 } label: { Image(systemName: "chevron.right").frame(width: 24, height: 56) }
                    .disabled(!canGoForward).accessibilityLabel("Następny tydzień")
            }
            .foregroundStyle(FormaColor.ink2)
        }
    }

    private func dayCell(_ day: Date, letter: String) -> some View {
        let session = plan.session(on: day)
        let hasSession = session != nil
        let isSelected = selected?.id == session?.id && hasSession
        let isToday = Self.calendar.isDateInToday(day)
        return Button { selectedDate = day; weekShift = 0 } label: {
            VStack(spacing: 4) {
                Text(letter).font(.system(size: 12, weight: .bold))
                Text(day.formatted(.dateTime.day())).font(.formaNumber(15)).monospacedDigit()
                Circle()
                    .fill(hasSession ? (isSelected ? FormaColor.onVolt : FormaColor.voltText) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .foregroundStyle(isSelected ? FormaColor.onVolt : (isToday ? FormaColor.voltText : FormaColor.ink2))
            .background(isSelected ? FormaColor.volt : FormaColor.well, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(isToday ? FormaColor.voltText.opacity(0.5) : .clear))
        }
        .buttonStyle(.plain)
        .disabled(!hasSession)
        .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))\(hasSession ? ", jest trening" : ", wolne")")
    }

    /// The plan covers a fixed number of weeks; when they are over the next plan is one tap away.
    private var endedCard: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            Text("Ten plan dobiegł końca").formaStyle(.title2).foregroundStyle(FormaColor.ink)
            Text("Ułożymy kolejny od dziś, z tymi samymi ustawieniami.")
                .formaStyle(.subheadline).foregroundStyle(FormaColor.ink3)
            Button {
                rebuilding = true
                Task { _ = await store.rebuildPlan(); rebuilding = false; selectedDate = nil; weekShift = 0 }
            } label: { Text(rebuilding ? "Układam…" : "Ułóż nowy plan") }
                .buttonStyle(.formaPrimary).disabled(rebuilding)
        }
        .padding(FormaSpacing.xl).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    /// "Cofnij" for the last change made by hand.
    @ViewBuilder
    private var undoBar: some View {
        if let last = store.lastEdit {
            HStack(spacing: FormaSpacing.m) {
                Text(last.summary).formaStyle(.subheadline).foregroundStyle(FormaColor.ink)
                Spacer()
                Button("Cofnij") { store.undoLastEdit() }.foregroundStyle(FormaColor.voltText).formaStyle(.subheadline)
                Button { store.dismissLastEdit() } label: { Image(systemName: "xmark") }
                    .foregroundStyle(FormaColor.ink3).accessibilityLabel("Ukryj")
            }
            .padding(FormaSpacing.l).glassCard(radius: 20)
            .padding(.horizontal, FormaSpacing.screen).padding(.bottom, 96)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var emptyState: some View {
        Text("Nie masz jeszcze planu. Ułożymy go po onboardingu.")
            .formaStyle(.body).foregroundStyle(FormaColor.ink2)
            .padding(FormaSpacing.xl).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    /// The play button of an exercise starts the workout from that exercise.
    private func start(_ planned: PlannedExercise, in session: PlannedSession) {
        guard let index = session.exercises.firstIndex(where: { $0.exerciseId == planned.exerciseId }) else { return }
        workout = WorkoutLaunch(session: session, startExercise: index)
    }
}

private struct SessionDetail: View {
    @Environment(AppStore.self) private var store
    let adjustment: PlanAdjustment
    let restored: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onRestore: () -> Void
    let onStartWorkout: () -> Void
    let onShowLog: () -> Void
    let onStart: (PlannedExercise) -> Void

    private var session: PlannedSession { adjustment.session }
    private var adapted: Bool { adjustment.isChanged }

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            HStack {
                SectionLabel(Self.label(for: session))
                Spacer()
                if session.status == .skipped {
                    Label("Pominięta", systemImage: "forward.end").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(FormaColor.ink3)
                } else if adapted {
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
            if session.status == .skipped {
                Button(action: onRestore) { Text("Przywróć sesję").frame(maxWidth: .infinity) }.buttonStyle(.formaGlass)
            } else if session.status == .done {
                Button(action: onShowLog) { Label("Zobacz zapis treningu", systemImage: "list.bullet.clipboard").frame(maxWidth: .infinity) }
                    .buttonStyle(.formaGlass)
            } else {
                Button(action: onStartWorkout) { Label("Zacznij trening", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.formaPrimary)
                Button(action: onEdit) { Label("Edytuj sesję", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity) }
                    .buttonStyle(.formaGlass)
            }
        }
        .padding(FormaSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .opacity(session.status == .skipped ? 0.6 : 1)
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
            // Starts the workout from this exercise (the earlier ones are left out).
            if session.status != .done, session.status != .skipped {
                Button { onStart(item) } label: {
                    Image(systemName: "play.fill").font(.system(size: 14, weight: .bold))
                        .frame(width: 38, height: 38)
                        .foregroundStyle(FormaColor.onVolt)
                        .background(FormaColor.volt, in: Circle())
                }
                .accessibilityLabel("Zacznij trening od tego ćwiczenia")
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

    /// "Środa, 8 października" (the weekday alone for a session without a date).
    private static func label(for session: PlannedSession) -> String {
        guard let date = session.date else { return dayNames[session.weekday - 1] }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized
    }
}

#Preview {
    PlanView()
        .environment(AppStore(onboardingStorage: InMemoryOnboardingStorage()))
        .preferredColorScheme(.dark)
}
