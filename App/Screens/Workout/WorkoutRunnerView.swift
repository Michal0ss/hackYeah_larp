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
        .sheet(isPresented: Binding(get: { coachContext != nil }, set: { if !$0 { coachContext = nil } })) {
            CoachView(workout: coachContext, onClose: { coachContext = nil })
        }
        .confirmationDialog("Zakończyć trening?", isPresented: $confirmExit, titleVisibility: .visible) {
            Button("Zapisz i zakończ") { model?.endEarly() }
            Button("Wyjdź bez zapisywania sesji", role: .destructive) { onClose() }
            Button("Wróć do treningu", role: .cancel) {}
        } message: {
            Text("Zapisane serie zostają. Sesja liczy się jako wykonana po „Zapisz i zakończ”.")
        }
    }

    @ViewBuilder
    private func phase(_ model: WorkoutModel) -> some View {
        switch model.run.phase {
        case .overview:
            WorkoutOverviewView(model: model, startExercise: startExercise, onStart: { model.begin() }, onClose: onClose)
        case .performing:
            performing(model)
        case .resting:
            SetReviewView(model: model, onAskCoach: { coachContext = model.coachContext(screen: .rest) },
                          onClose: { confirmExit = true })
        case .finished:
            WorkoutFinishedView(model: model, onDone: {
                model.save()
                onClose()
            })
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
                            onAskCoach: { coachContext = model.coachContext(screen: .liveSet) })
                    .id(key)
            } else {
                ManualSetView(model: model, planned: planned, exercise: exercise,
                              onAskCoach: { coachContext = model.coachContext(screen: .liveSet) },
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
    let onDone: () -> Void

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
                Button(action: onDone) {
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
    static func weight(_ kg: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pl_PL")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return (formatter.string(from: NSNumber(value: kg)) ?? "\(kg)") + " kg"
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
