import SwiftUI
import Contracts
import DesignSystem
import Plan

/// The record of a finished session: the sets by exercise, each of which can be corrected, and a set can be added that
/// was not entered during the workout.
struct WorkoutLogSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let session: PlannedSession

    @State private var sets: [LoggedSet] = []
    @State private var editing: LoggedSet?
    @State private var adding: PlannedExercise?

    private var log: TrainingLogStore { store.services.trainingLog }

    var body: some View {
        ZStack {
            AmbientBackground()
            VerticalScrollView {
                VStack(alignment: .leading, spacing: FormaSpacing.l) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            SectionLabel("Zapis treningu")
                            Text(session.title).formaStyle(.title).foregroundStyle(FormaColor.ink)
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(FormaColor.ink)
                                .frame(width: 44, height: 44).glassCapsule(interactive: true)
                        }
                        .accessibilityLabel("Zamknij")
                    }
                    ForEach(session.exercises) { planned in exerciseCard(planned) }
                }
                .padding(.horizontal, FormaSpacing.screen)
                .padding(.top, FormaSpacing.l)
                .padding(.bottom, FormaSpacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear(perform: reload)
        .sheet(item: $editing) { set in
            let timed = set.seconds != nil && set.reps == nil
            EditSetSheet(heading: "Seria \(set.setIndex)", timed: timed, value: set.reps ?? set.seconds ?? 0, weight: set.weightKg,
                         fromCamera: set.source == .live, suggestedWeight: set.weightKg ?? log.lastWeight(exerciseId: set.exerciseId)) { value, weight in
                log.edit(set.id, reps: timed ? nil : value, seconds: timed ? value : nil, weightKg: .some(weight))
                reload()
            }
        }
        .sheet(item: $adding) { planned in
            let timed = store.exercise(id: planned.exerciseId)?.timed ?? false
            let number = (sets.filter { $0.exerciseId == planned.exerciseId }.map(\.setIndex).max() ?? 0) + 1
            EditSetSheet(heading: "Seria \(number)", timed: timed, value: timed ? planned.repsMin : planned.repsMax, weight: nil,
                         suggestedWeight: log.lastWeight(exerciseId: planned.exerciseId)) { value, weight in
                log.record(LoggedSet(sessionId: session.id, exerciseId: planned.exerciseId, setIndex: number,
                                     reps: timed ? nil : value, seconds: timed ? value : nil, weightKg: weight, source: .manual))
                reload()
            }
        }
    }

    private func reload() { sets = log.sets(forSession: session.id) }

    private func exerciseCard(_ planned: PlannedExercise) -> some View {
        let exercise = store.exercise(id: planned.exerciseId)
        let own = sets.filter { $0.exerciseId == planned.exerciseId }.sorted { $0.setIndex < $1.setIndex }
        return VStack(alignment: .leading, spacing: FormaSpacing.m) {
            Text(exercise?.name ?? planned.exerciseId).formaStyle(.headline).foregroundStyle(FormaColor.ink)
            if own.isEmpty {
                Text("Brak zapisanych serii").formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            }
            ForEach(own) { set in
                HStack {
                    Text("Seria \(set.setIndex)").formaStyle(.subheadline).foregroundStyle(FormaColor.ink2)
                    Spacer()
                    Text(line(set)).font(.formaNumber(15)).monospacedDigit().foregroundStyle(FormaColor.ink)
                    Button { editing = set } label: { Image(systemName: "pencil").frame(width: 36, height: 36) }
                        .buttonStyle(.plain).foregroundStyle(FormaColor.voltText).accessibilityLabel("Edytuj serię \(set.setIndex)")
                }
            }
            Button { adding = planned } label: { Label("Dodaj serię", systemImage: "plus").frame(maxWidth: .infinity) }
                .buttonStyle(.formaGlass)
        }
        .padding(FormaSpacing.xl).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private func line(_ set: LoggedSet) -> String {
        var parts = [set.reps.map { "\($0) powt." } ?? set.seconds.map { "\($0) s" } ?? "-"]
        if let weight = set.weightKg { parts.append(WorkoutFormat.weight(weight)) }
        return parts.joined(separator: " · ")
    }
}
