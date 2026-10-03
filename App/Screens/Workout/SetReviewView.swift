import SwiftUI
import Contracts
import DesignSystem
import Plan
#if os(iOS)
import AudioToolbox
import UIKit
#endif

/// Right after a set: the result, the rest timer, what comes next, and the way to ask the coach.
struct SetReviewView: View {
    let model: WorkoutModel
    let onAskCoach: () -> Void
    let onClose: () -> Void

    @State private var editing: LoggedSet?
    @State private var showDetails = false
    @State private var cued = false

    private var run: WorkoutRun { model.run }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FormaSpacing.l) {
                topBar
                if let set = run.lastSet, let planned = planned(for: set) {
                    header(set, planned)
                    resultCard(set, planned)
                }
                if let rest = run.rest { restCard(rest) }
                upNext
                actions
            }
            .padding(.horizontal, FormaSpacing.screen)
            .padding(.top, FormaSpacing.l)
            .padding(.bottom, FormaSpacing.xxl)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $editing) { set in
            let timed = set.seconds != nil && set.reps == nil
            EditSetSheet(heading: "Seria \(set.setIndex)", timed: timed, value: set.reps ?? set.seconds ?? 0, weight: set.weightKg,
                         fromCamera: set.source == .live, suggestedWeight: set.weightKg ?? model.lastWeight(set.exerciseId)) { value, weight in
                model.edit(set, reps: timed ? nil : value, seconds: timed ? value : nil, weightKg: weight)
            }
        }
        .sheet(isPresented: $showDetails) {
            if let id = run.lastSet?.liveSetId, let summary = model.liveSummaries[id] {
                SetSummaryView(summary: summary, exerciseName: model.exercise(run.currentExercise ?? run.session.exercises[0])?.name ?? "",
                               totalSets: run.setsInCurrentExercise, showsActions: false, onNextSet: {}, onClose: { showDetails = false })
            }
        }
    }

    private func planned(for set: LoggedSet) -> PlannedExercise? {
        run.session.exercises.first { $0.exerciseId == set.exerciseId }
    }

    // MARK: parts

    private var topBar: some View {
        HStack {
            SectionLabel("Po serii")
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(FormaColor.ink)
                    .frame(width: 44, height: 44).glassCapsule(interactive: true)
            }
            .accessibilityLabel("Zakończ trening")
        }
    }

    private func header(_ set: LoggedSet, _ planned: PlannedExercise) -> some View {
        VStack(alignment: .leading, spacing: FormaSpacing.s) {
            Text("Seria \(set.setIndex) z \(planned.sets)").formaStyle(.caption).foregroundStyle(FormaColor.ink3)
            Text(model.exercise(planned)?.name ?? planned.exerciseId).formaStyle(.largeTitle).foregroundStyle(FormaColor.ink)
            if let id = set.liveSetId, model.liveSummaries[id]?.isSimulated == true { SimulatedBadge() }
        }
    }

    private func resultCard(_ set: LoggedSet, _ planned: PlannedExercise) -> some View {
        let timed = model.isTimed(planned)
        let summary = set.liveSetId.flatMap { model.liveSummaries[$0] }
        return VStack(alignment: .leading, spacing: FormaSpacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: FormaSpacing.s) {
                NumberText("\(timed ? (set.seconds ?? 0) : (set.reps ?? 0))", size: 64)
                Text(timed ? "sekund" : "powtórzeń").formaStyle(.caption).foregroundStyle(FormaColor.ink3)
                Spacer()
                if set.isEdited { Label("poprawione", systemImage: "pencil").font(.system(size: 12, weight: .bold)).foregroundStyle(FormaColor.ink3) }
            }
            Text("w planie \(planned.repsMin)–\(planned.repsMax)\(timed ? " s" : "")")
                .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            HStack(spacing: FormaSpacing.s) {
                Image(systemName: "scalemass").foregroundStyle(FormaColor.ink3).accessibilityHidden(true)
                Text(set.weightKg.map(WorkoutFormat.weight) ?? "bez wpisanego ciężaru")
                    .formaStyle(.subheadline).foregroundStyle(FormaColor.ink2)
            }
            if let summary {
                HStack(spacing: FormaSpacing.l) {
                    chip("Technika", summary.techniqueScore.map(String.init) ?? "-")
                    chip("Tempo", "\(summary.tempoScore)")
                }
                if let finding = summary.techniqueFindings.first(where: { $0.severity != .good }) {
                    Label(finding.title, systemImage: "exclamationmark.triangle.fill")
                        .formaStyle(.subheadline).foregroundStyle(FormaColor.moderateText)
                }
            }
            HStack(spacing: FormaSpacing.s) {
                Button { editing = set } label: { Label("Edytuj wynik", systemImage: "pencil").frame(maxWidth: .infinity) }
                    .buttonStyle(.formaGlass)
                if summary != nil {
                    Button { showDetails = true } label: { Text("Szczegóły").frame(maxWidth: .infinity) }
                        .buttonStyle(.formaGlass)
                }
            }
        }
        .padding(FormaSpacing.xl).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private func chip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NumberText(value, size: 30)
            Text(title).formaStyle(.caption).foregroundStyle(FormaColor.ink3)
        }
    }

    private func restCard(_ rest: RestTimer) -> some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let remaining = rest.remaining(at: context.date)
            let finished = rest.isFinished(at: context.date)
            HStack(spacing: FormaSpacing.l) {
                ProgressRing(progress: rest.progress(at: context.date), lineWidth: 10,
                             color: finished ? FormaColor.go : FormaColor.volt) {
                    Text(finished ? "Gotowe" : WorkoutFormat.clock(remaining))
                        .font(.formaNumber(finished ? 15 : 22)).monospacedDigit().foregroundStyle(FormaColor.ink)
                }
                .frame(width: 104, height: 104)
                VStack(alignment: .leading, spacing: FormaSpacing.s) {
                    Text(finished ? "Koniec odpoczynku" : "Odpoczynek").formaStyle(.headline).foregroundStyle(FormaColor.ink)
                    Text(finished ? "Zacznij, gdy telefon stoi w kadrze." : "Zacznij następną serię, gdy będziesz gotowy.")
                        .formaStyle(.footnote).foregroundStyle(FormaColor.ink3).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: FormaSpacing.s) {
                        timerButton("−15 s", "Skróć odpoczynek o 15 sekund") { model.extendRest(-RestTimer.step) }
                        timerButton("+15 s", "Wydłuż odpoczynek o 15 sekund") { model.extendRest(RestTimer.step) }
                        if !finished { timerButton("Pomiń", "Pomiń odpoczynek") { model.skipRest() } }
                    }
                }
            }
            .onChange(of: finished) { _, isFinished in
                if isFinished, !cued { cue() }
                if !isFinished { cued = false }
            }
        }
        .padding(FormaSpacing.xl).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private func timerButton(_ title: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(FormaColor.ink)
                .padding(.horizontal, 10).frame(height: 36).background(FormaColor.well, in: Capsule())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    /// The rest is over: a short vibration and a sound (only while the app is on screen).
    private func cue() {
        cued = true
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlaySystemSound(1007)
        #endif
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dalej").formaStyle(.caption).foregroundStyle(FormaColor.ink3)
            switch run.upcoming {
            case .set(let number, let total):
                Text("Seria \(number) z \(total)").formaStyle(.headline).foregroundStyle(FormaColor.ink)
            case .exercise(let planned):
                Text(model.exercise(planned)?.name ?? planned.exerciseId).formaStyle(.headline).foregroundStyle(FormaColor.ink)
                Text("\(planned.sets) × \(planned.repsMin)–\(planned.repsMax)").formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            case .finished:
                Text("To była ostatnia seria").formaStyle(.headline).foregroundStyle(FormaColor.ink)
            }
        }
        .padding(FormaSpacing.xl).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private var actions: some View {
        VStack(spacing: FormaSpacing.m) {
            Button(action: onAskCoach) { Label("Zapytaj trenera", systemImage: "bubble.left.and.text.bubble.right").frame(maxWidth: .infinity) }
                .buttonStyle(.formaGlass)
            Button { model.next() } label: { Text(nextTitle).frame(maxWidth: .infinity) }
                .buttonStyle(.formaPrimary)
            if run.upcoming != .finished {
                Button("Pomiń resztę tego ćwiczenia") { model.skipExercise() }
                    .formaStyle(.subheadline).foregroundStyle(FormaColor.ink3)
            }
        }
    }

    private var nextTitle: String {
        switch run.upcoming {
        case .set(let number, _): return "Zacznij serię \(number)"
        case .exercise: return "Następne ćwiczenie"
        case .finished: return "Zakończ trening"
        }
    }
}
