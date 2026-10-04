import SwiftUI
import Contracts
import DesignSystem
import Plan

/// Asks for a workout: the session to do (as the user sees it, adjusted for today) and where to start.
struct WorkoutLaunch: Identifiable {
    let id = UUID()
    let session: PlannedSession
    var startExercise = 0
}

/// A whole session from the plan, exercise after exercise: overview, sets (live coach or typed in), the screen after
/// each set with the rest timer and the coach, and the end. Design: WORKOUT_FLOW.md.
struct WorkoutRunnerView: View {
    let session: PlannedSession
    /// Index of the exercise to start from (the user tapped "zacznij od tego").
    var startExercise = 0
    let onClose: () -> Void

    @Environment(AppStore.self) private var store
    @State private var model: WorkoutModel?
    @State private var confirmExit = false
    @State private var coachContext: WorkoutContext?
    /// Set when the coach is opened by a "Przeprowadź mnie" button: asked as soon as the sheet opens.
    @State private var guideQuestion: String?

    var body: some View {
        ZStack {
            AmbientBackground()
            if let model {
                phase(model)
            }
        }
        .onAppear {
            if model == nil { model = WorkoutModel(session: session, store: store, startExercise: startExercise) }
        }
        .sheet(isPresented: Binding(get: { coachContext != nil }, set: { if !$0 { coachContext = nil; guideQuestion = nil } })) {
            CoachView(workout: coachContext, initialQuestion: guideQuestion,
                      onClose: { coachContext = nil; guideQuestion = nil })
        }
        .confirmationDialog("Zakończyć trening?", isPresented: $confirmExit, titleVisibility: .visible) {
            Button("Zapisz i zakończ") { model?.endEarly() }
            Button("Wyjdź bez zapisywania sesji", role: .destructive) { onClose() }
            Button("Wróć do treningu", role: .cancel) {}
        } message: {
            Text("Zapisane serie zostają. Sesja liczy się jako wykonana po „Zapisz i zakończ”.")
        }
    }

    /// Opens the coach and asks `question` right away (nil: just opens it).
    private func askCoach(_ question: String?, screen: WorkoutScreen) {
        guideQuestion = question
        coachContext = model?.coachContext(screen: screen)
    }

    @ViewBuilder
    private func phase(_ model: WorkoutModel) -> some View {
        switch model.run.phase {
        case .overview:
            WorkoutOverviewView(model: model, startExercise: startExercise, onStart: { model.begin() },
                                onGuide: { askCoach(model.guideQuestion, screen: .plan) }, onClose: onClose)
        case .performing:
            performing(model)
        case .resting:
            SetReviewView(model: model, onAskCoach: { coachContext = model.coachContext(screen: .rest) },
                          onClose: { confirmExit = true })
        case .finished:
            WorkoutFinishedView(model: model, onAskCoach: { coachContext = model.coachContext(screen: .sessionFeedback) },
                                onDone: onClose)
        }
    }

    @ViewBuilder
    private func performing(_ model: WorkoutModel) -> some View {
        if let planned = model.run.currentExercise, let exercise = model.exercise(planned) {
            let key = "\(model.run.exerciseIndex)-\(model.run.setIndex)"
            if model.isLive(planned), let tempo = planned.tempo {
                LiveSetView(exercise: exercise, spec: tempo, setIndex: model.run.setIndex, totalSets: planned.sets,
                            onNextSet: {}, onClose: { confirmExit = true },
                            onFinished: { model.completeLive($0) },
                            onAskCoach: { coachContext = model.coachContext(screen: .liveSet) },
                            onSkipVideo: { model.skipVideo(planned) })
                    .id(key)
            } else {
                ManualSetView(model: model, planned: planned, exercise: exercise,
                              onAskCoach: { coachContext = model.coachContext(screen: .liveSet) },
                              onExplain: { askCoach(model.explainQuestion, screen: .liveSet) },
                              onClose: { confirmExit = true })
                    .id(key)
            }
        } else {
            // The exercise is not in the catalog any more: leave it out instead of getting stuck.
            Color.clear.onAppear { model.skipExercise() }
        }
    }
}

// MARK: - Overview

private struct WorkoutOverviewView: View {
    let model: WorkoutModel
    let startExercise: Int
    let onStart: () -> Void
    let onGuide: () -> Void
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FormaSpacing.l) {
                HStack {
                    SectionLabel("Trening")
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(FormaColor.ink)
                            .frame(width: 44, height: 44).glassCapsule(interactive: true)
                    }
                    .accessibilityLabel("Zamknij")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.session.title).formaStyle(.largeTitle).foregroundStyle(FormaColor.ink)
                    Text(subtitle).formaStyle(.subheadline).foregroundStyle(FormaColor.ink3)
                }
                VStack(spacing: 0) {
                    ForEach(Array(model.session.exercises.enumerated()), id: \.element.id) { index, planned in
                        row(planned, left: index < startExercise)
                        if index < model.session.exercises.count - 1 { Divider().overlay(FormaColor.line) }
                    }
                }
                .padding(FormaSpacing.l).frame(maxWidth: .infinity, alignment: .leading).glassCard()
                Button(action: onStart) { Text("Zacznij trening").frame(maxWidth: .infinity) }
                    .buttonStyle(.formaPrimary)
                if model.session.exercises.contains(where: model.canAnalyse) {
                    Toggle(isOn: Binding(get: { model.allVideoSkipped }, set: { model.setVideoSkippedForAll($0) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pomiń analizę wideo").formaStyle(.headline).foregroundStyle(FormaColor.ink)
                            Text("Wyniki wpiszesz ręcznie, bez kamery.").formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                        }
                    }
                    .tint(FormaColor.volt)
                    .padding(FormaSpacing.l).glassCard(radius: 22)
                }
                Button(action: onGuide) {
                    Label("Przeprowadź mnie przez trening", systemImage: "figure.walk.motion").frame(maxWidth: .infinity)
                }
                .buttonStyle(.formaGlass)
                Text("Trener AI wyjaśni każde ćwiczenie krok po kroku, zanim zaczniesz.")
                    .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            }
            .padding(.horizontal, FormaSpacing.screen)
            .padding(.top, FormaSpacing.l)
            .padding(.bottom, FormaSpacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    private var subtitle: String {
        let sets = model.session.exercises.dropFirst(startExercise).map(\.sets).reduce(0, +)
        return "\(model.session.exercises.count - startExercise) ćwiczeń · \(sets) serii"
    }

    private func row(_ planned: PlannedExercise, left: Bool) -> some View {
        let exercise = model.exercise(planned)
        let unit = model.isTimed(planned) ? " s" : ""
        return HStack(spacing: FormaSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise?.name ?? planned.exerciseId).formaStyle(.headline).foregroundStyle(FormaColor.ink)
                Text(model.isLive(planned) ? "z trenerem na żywo (kamera)" : "wpisujesz wynik ręcznie")
                    .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            }
            Spacer()
            Text("\(planned.sets) × \(planned.repsMin)–\(planned.repsMax)\(unit)")
                .font(.formaNumber(15)).monospacedDigit().foregroundStyle(FormaColor.ink2)
        }
        .padding(.vertical, 10)
        .opacity(left ? 0.4 : 1)
    }
}

// MARK: - Finished

private struct WorkoutFinishedView: View {
    let model: WorkoutModel
    let onAskCoach: () -> Void
    let onDone: () -> Void
    @State private var draft = SessionFeedbackDraft()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FormaSpacing.l) {
                SectionLabel("Koniec treningu")
                Text(model.session.title).formaStyle(.largeTitle).foregroundStyle(FormaColor.ink)
                HStack(spacing: FormaSpacing.xl) {
                    stat("\(model.run.completedSets)/\(model.run.plannedSets)", "serii")
                    stat("\(model.totalReps)", "powtórzeń")
                }
                .padding(FormaSpacing.xl).frame(maxWidth: .infinity, alignment: .leading).glassCard()
                VStack(alignment: .leading, spacing: FormaSpacing.m) {
                    ForEach(model.results) { result in resultRow(result) }
                }
                .padding(FormaSpacing.xl).frame(maxWidth: .infinity, alignment: .leading).glassCard()
                if model.run.completedSets == 0 {
                    Text("Nie zapisano żadnej serii, więc sesja nie liczy się jako wykonana.")
                        .formaStyle(.subheadline).foregroundStyle(FormaColor.ink3)
                }
                if model.run.completedSets > 0 {
                    SessionFeedbackCard(draft: $draft, sessionId: model.session.id,
                                        completedSets: model.run.completedSets, plannedSets: model.run.plannedSets)
                    Button(action: onAskCoach) {
                        Label("Zapytaj trenera", systemImage: "bubble.left.and.text.bubble.right").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.formaGlass)
                }
                Button {
                    model.save(feedback: draft.build(sessionId: model.session.id, completedSets: model.run.completedSets,
                                                     plannedSets: model.run.plannedSets))
                    onDone()
                } label: {
                    Text(model.run.completedSets == 0 ? "Zamknij" : "Zapisz i zakończ").frame(maxWidth: .infinity)
                }
                .buttonStyle(.formaPrimary)
            }
            .padding(.horizontal, FormaSpacing.screen)
            .padding(.top, FormaSpacing.l)
            .padding(.bottom, FormaSpacing.xxl)
        }
        .scrollIndicators(.hidden)
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NumberText(value, size: 44)
            Text(caption).formaStyle(.caption).foregroundStyle(FormaColor.ink3)
        }
    }

    private func resultRow(_ result: WorkoutModel.ExerciseResult) -> some View {
        let name = model.exercise(result.planned)?.name ?? result.planned.exerciseId
        return VStack(alignment: .leading, spacing: 2) {
            Text(name).formaStyle(.headline).foregroundStyle(FormaColor.ink)
            if result.skipped && result.sets.isEmpty {
                Text("pominięte").formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            } else if result.sets.isEmpty {
                Text("niewykonane").formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            } else {
                Text(WorkoutFormat.summary(of: result.sets, planned: result.planned.sets))
                    .formaStyle(.subheadline).foregroundStyle(FormaColor.ink2)
            }
        }
    }
}

/// Short Polish texts for sets.
enum WorkoutFormat {
    /// One formatter for all weights: building a `NumberFormatter` is expensive and these run while lists are drawn.
    private static let weightFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    /// "12,5" for 12.5, "12" for 12. Nil only if the formatter fails.
    static func number(_ value: Double) -> String? { weightFormatter.string(from: NSNumber(value: value)) }

    static func weight(_ kg: Double) -> String {
        (number(kg) ?? "\(kg)") + " kg"
    }

    /// "3 z 4 serii · 8, 8, 7 powt. · 17,5 kg"
    static func summary(of sets: [LoggedSet], planned: Int) -> String {
        let ordered = sets.sorted { $0.setIndex < $1.setIndex }
        var parts = ["\(ordered.count) z \(planned) serii"]
        let numbers = ordered.map { $0.reps.map(String.init) ?? $0.seconds.map { "\($0) s" } ?? "-" }
        parts.append(numbers.joined(separator: ", ") + (ordered.first?.reps != nil ? " powt." : ""))
        let weights = Set(ordered.compactMap(\.weightKg))
        if weights.count == 1, let one = weights.first { parts.append(weight(one)) }
        else if weights.count > 1, let top = weights.max() { parts.append("do \(weight(top))") }
        return parts.joined(separator: " · ")
    }

    /// 90 → "1:30"
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
