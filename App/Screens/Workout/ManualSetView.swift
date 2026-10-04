import SwiftUI
import Contracts
import DesignSystem
import Plan
#if os(iOS)
import UIKit
#endif

/// A set of an exercise without live analysis: the user types the result (reps, or seconds for a plank) and, if they
/// like, the weight. The weight starts from the last time; it is saved only when it is switched on.
struct ManualSetView: View {
    let model: WorkoutModel
    let planned: PlannedExercise
    let exercise: ExerciseItem
    let onAskCoach: () -> Void
    let onExplain: () -> Void
    let onClose: () -> Void

    @State private var value: Int
    @State private var weight: Double?
    /// Moment the stopwatch was started.
    @State private var startedAt: Date?
    /// What the stopwatch showed when it was stopped.
    @State private var stoppedAt = 0
    /// The target of a timed exercise was reached (one vibration).
    @State private var reachedTarget = false

    init(model: WorkoutModel, planned: PlannedExercise, exercise: ExerciseItem, onAskCoach: @escaping () -> Void,
         onExplain: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.model = model
        self.planned = planned
        self.exercise = exercise
        self.onAskCoach = onAskCoach
        self.onExplain = onExplain
        self.onClose = onClose
        // Start from the top of the planned range: "Zrobione" alone records what was asked for.
        _value = State(initialValue: planned.repsMax)
        _weight = State(initialValue: nil)
    }

    private var timed: Bool { exercise.timed ?? false }
    private var run: WorkoutRun { model.run }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FormaSpacing.l) {
                topBar
                VStack(alignment: .leading, spacing: FormaSpacing.s) {
                    Text("Seria \(run.setIndex) z \(planned.sets)").formaStyle(.caption).foregroundStyle(FormaColor.ink3)
                    Text(exercise.name).formaStyle(.largeTitle).foregroundStyle(FormaColor.ink)
                    Text("w planie \(planned.repsMin)–\(planned.repsMax)\(timed ? " s" : " powtórzeń")")
                        .formaStyle(.subheadline).foregroundStyle(FormaColor.ink3)
                }
                stopwatch
                VStack(alignment: .leading, spacing: FormaSpacing.m) {
                    SectionLabel("Wynik")
                    SetNumbersEditor(timed: timed, value: $value, weight: $weight,
                                     suggestedWeight: model.lastWeight(exercise.id))
                }
                .padding(FormaSpacing.xl).frame(maxWidth: .infinity, alignment: .leading).glassCard()
                VStack(spacing: FormaSpacing.m) {
                    Button {
                        model.completeManual(reps: timed ? nil : value, seconds: timed ? value : nil, weightKg: weight)
                    } label: { Text("Zrobione").frame(maxWidth: .infinity) }
                        .buttonStyle(.formaPrimary)
                    Button(action: onExplain) { Label("Wytłumacz to ćwiczenie", systemImage: "figure.walk.motion").frame(maxWidth: .infinity) }
                        .buttonStyle(.formaGlass)
                    Button(action: onAskCoach) { Label("Zapytaj trenera", systemImage: "bubble.left.and.text.bubble.right").frame(maxWidth: .infinity) }
                        .buttonStyle(.formaGlass)
                    Button("Pomiń to ćwiczenie") { model.skipExercise() }
                        .formaStyle(.subheadline).foregroundStyle(FormaColor.ink3)
                }
            }
            .padding(.horizontal, FormaSpacing.screen)
            .padding(.top, FormaSpacing.l)
            .padding(.bottom, FormaSpacing.xxl)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            // The weight of the last time is offered, not assumed: it is saved only when the toggle is on.
            if weight == nil, let last = model.lastWeight(exercise.id) { weight = last }
        }
    }

    private var topBar: some View {
        HStack {
            SectionLabel("Seria")
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(FormaColor.ink)
                    .frame(width: 44, height: 44).glassCapsule(interactive: true)
            }
            .accessibilityLabel("Zakończ trening")
        }
    }

    /// A stopwatch for every set typed in. For an exercise counted in time, "Stop" puts the seconds in the result (it can
    /// still be changed) and the phone vibrates once when the planned time is reached.
    private var stopwatch: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let elapsed = startedAt.map { max(0, Int(context.date.timeIntervalSince($0))) } ?? stoppedAt
            VStack(alignment: .leading, spacing: FormaSpacing.m) {
                SectionLabel(timed ? "Stoper (cel \(planned.repsMin) s)" : "Stoper serii")
                HStack {
                    NumberText(WorkoutFormat.clock(TimeInterval(elapsed)), size: 56)
                        .lineLimit(1).minimumScaleFactor(0.6).layoutPriority(1)
                    Spacer(minLength: FormaSpacing.s)
                    if startedAt == nil, stoppedAt > 0 {
                        Button("Zeruj") { stoppedAt = 0; reachedTarget = false }
                            .formaStyle(.subheadline).foregroundStyle(FormaColor.ink3)
                    }
                    Button {
                        if let started = startedAt {
                            stoppedAt = max(1, Int(Date().timeIntervalSince(started)))
                            if timed { value = stoppedAt }
                            startedAt = nil
                        } else {
                            if stoppedAt > 0 { stoppedAt = 0 }
                            reachedTarget = false
                            startedAt = Date()
                        }
                    } label: {
                        Text(startedAt == nil ? "Start" : "Stop").frame(minWidth: 72)
                    }
                    .buttonStyle(.formaPrimary)
                }
            }
            .padding(FormaSpacing.xl).frame(maxWidth: .infinity, alignment: .leading).glassCard()
            .onChange(of: elapsed) { _, now in
                if timed, startedAt != nil, !reachedTarget, now >= planned.repsMin {
                    reachedTarget = true
                    #if os(iOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    #endif
                }
            }
        }
    }
}

/// The numbers of a set: reps (or seconds) and an optional weight. Used when doing a set by hand and when correcting one.
/// The weight is added with a button, changed with the steps or typed in, and taken away with another button.
struct SetNumbersEditor: View {
    let timed: Bool
    @Binding var value: Int
    /// nil = no weight.
    @Binding var weight: Double?
    /// What "Dodaj ciężar" starts from.
    var suggestedWeight: Double?

    @State private var weightText = ""
    @FocusState private var typing: Bool

    private var step: Int { timed ? 5 : 1 }
    private var range: ClosedRange<Int> { timed ? 1...LoggedSetLimits.seconds.upperBound : 0...LoggedSetLimits.reps.upperBound }

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.l) {
            HStack(spacing: FormaSpacing.l) {
                roundButton("minus", timed ? "Mniej sekund" : "Mniej powtórzeń") { value = max(range.lowerBound, value - step) }
                VStack(spacing: 0) {
                    NumberText("\(value)", size: 56)
                    Text(timed ? "sekund" : "powtórzeń").formaStyle(.caption).foregroundStyle(FormaColor.ink3)
                }
                .frame(maxWidth: .infinity)
                roundButton("plus", timed ? "Więcej sekund" : "Więcej powtórzeń") { value = min(range.upperBound, value + step) }
            }
            weightSection
        }
        .onAppear { weightText = Self.text(weight) }
        .onChange(of: weight) { _, new in if !typing { weightText = Self.text(new) } }
    }

    @ViewBuilder
    private var weightSection: some View {
        if weight != nil {
            VStack(alignment: .leading, spacing: FormaSpacing.m) {
                Text("Ciężar").formaStyle(.headline).foregroundStyle(FormaColor.ink)
                HStack(spacing: FormaSpacing.s) {
                    weightButton("−2,5", -2.5)
                    weightButton("−0,5", -0.5)
                    HStack(spacing: 4) {
                        TextField("0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .focused($typing)
                            .multilineTextAlignment(.trailing)
                            .font(.formaNumber(20)).monospacedDigit().foregroundStyle(FormaColor.ink)
                            .onChange(of: weightText) { _, text in
                                if typing, let parsed = Self.parse(text) { weight = parsed }
                            }
                        Text("kg").font(.formaNumber(16)).foregroundStyle(FormaColor.ink3)
                    }
                    .frame(maxWidth: .infinity)
                    weightButton("+0,5", 0.5)
                    weightButton("+2,5", 2.5)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Gotowe") { typing = false }
                    }
                }
                Button("Bez ciężaru") { typing = false; weight = nil }
                    .formaStyle(.subheadline).foregroundStyle(FormaColor.ink3)
            }
        } else {
            Button { weight = suggestedWeight ?? 5 } label: {
                Label("Dodaj ciężar", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .buttonStyle(.formaGlass)
        }
    }

    private func roundButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 20, weight: .bold)).foregroundStyle(FormaColor.ink)
                .frame(width: 56, height: 56).background(FormaColor.well, in: Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    private func weightButton(_ title: String, _ delta: Double) -> some View {
        Button {
            typing = false
            weight = min(LoggedSetLimits.weightKg.upperBound, max(0.5, (weight ?? 0) + delta))
        } label: {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(FormaColor.ink)
                .padding(.horizontal, 10).frame(minWidth: 44, minHeight: 44).background(FormaColor.well, in: Capsule())
        }
        .buttonStyle(.plain).accessibilityLabel("Ciężar \(title) kilograma")
    }

    /// "12,5" for 12.5, "12" for 12, "" for none.
    static func text(_ weight: Double?) -> String {
        guard let weight else { return "" }
        return WorkoutFormat.number(weight) ?? ""
    }

    /// Accepts a comma or a dot; nil for anything that is not a number above zero.
    static func parse(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let number = Double(cleaned), number > 0 else { return nil }
        return min(number, LoggedSetLimits.weightKg.upperBound)
    }
}

/// Correcting a set after the fact, or adding one: reps (or seconds) and weight. The camera's technique and tempo
/// scores stay as measured. The caller decides what saving does.
struct EditSetSheet: View {
    @Environment(\.dismiss) private var dismiss
    let heading: String
    let timed: Bool
    let fromCamera: Bool
    let suggestedWeight: Double?
    let onSave: (_ value: Int, _ weightKg: Double?) -> Void

    @State private var value: Int
    @State private var weight: Double?

    init(heading: String, timed: Bool, value: Int, weight: Double?, fromCamera: Bool = false, suggestedWeight: Double? = nil,
         onSave: @escaping (_ value: Int, _ weightKg: Double?) -> Void) {
        self.heading = heading
        self.timed = timed
        self.fromCamera = fromCamera
        self.suggestedWeight = suggestedWeight
        self.onSave = onSave
        _value = State(initialValue: value)
        _weight = State(initialValue: weight)
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(alignment: .leading, spacing: FormaSpacing.l) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel("Edytuj wynik")
                        Text(heading).formaStyle(.title2).foregroundStyle(FormaColor.ink)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(FormaColor.ink)
                            .frame(width: 44, height: 44).glassCapsule(interactive: true)
                    }
                    .accessibilityLabel("Zamknij")
                }
                if fromCamera {
                    Text("Ocena techniki i tempa zostaje taka, jak zmierzyła kamera. Poprawiasz liczbę powtórzeń i ciężar.")
                        .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SetNumbersEditor(timed: timed, value: $value, weight: $weight, suggestedWeight: suggestedWeight)
                    .padding(FormaSpacing.xl).frame(maxWidth: .infinity, alignment: .leading).glassCard()
                Button {
                    onSave(value, weight)
                    dismiss()
                } label: { Text("Zapisz").frame(maxWidth: .infinity) }
                    .buttonStyle(.formaPrimary)
                Spacer()
            }
            .padding(.horizontal, FormaSpacing.screen)
            .padding(.top, FormaSpacing.l)
        }
        .presentationDetents([.medium, .large])
    }
}
