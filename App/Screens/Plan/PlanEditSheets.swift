import SwiftUI
import Contracts
import DesignSystem
import Plan

/// Editing a session by hand: sets, reps and rest, swapping, adding, removing and ordering exercises, moving the
/// session to another day, skipping it. Every tap changes the plan at once (the same checks as for the coach's
/// proposals), and the Plan screen offers "Cofnij" for the last change.
struct SessionEditSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let sessionId: UUID

    @State private var scope: PlanEditScope = .thisSession
    @State private var error: String?
    @State private var picking: ExercisePick?
    @State private var moveTo = Date()
    @State private var confirmRemove = false

    private static let calendar = TrainingPlan.calendar

    /// "poniedziałek, 5 października" → "Poniedziałek, 5 października".
    private static func sentenceCase(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

    private var session: PlannedSession? { store.plan.sessions.first { $0.id == sessionId } }

    /// Later sessions with the same title that a change "for this and the following" would also reach.
    private var followingCount: Int {
        guard let session, let date = session.date else { return 0 }
        return store.plan.sessions.filter {
            $0.title == session.title && ($0.date ?? .distantPast) > date && $0.status == .planned
        }.count
    }

    /// From today to the last day of the plan.
    private var days: ClosedRange<Date> {
        let today = Self.calendar.startOfDay(for: Date())
        guard let start = store.plan.startDate, let weeks = store.plan.weeks,
              let end = Self.calendar.date(byAdding: .day, value: weeks * 7 - 1, to: Self.calendar.startOfDay(for: start)),
              end >= today else { return today...today }
        return today...end
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            VerticalScrollView {
                VStack(alignment: .leading, spacing: FormaSpacing.l) {
                    topBar
                    if let session {
                        header(session)
                        if let error { errorBanner(error) }
                        if session.status == .skipped {
                            skippedCard
                        } else {
                            if followingCount > 0 { scopeCard }
                            exercisesCard(session)
                            dayCard
                        }
                        removeCard(session)
                    }
                }
                .padding(.horizontal, FormaSpacing.screen)
                .padding(.top, FormaSpacing.l)
                .padding(.bottom, FormaSpacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { if let date = session?.date { moveTo = max(date, days.lowerBound) } }
        .sheet(item: $picking) { pick in
            ExercisePickerSheet(title: pick.title, candidates: store.exerciseCandidates(excluding: pick.excluded, timed: pick.timed)) { id in
                switch pick.purpose {
                case .swap(let old): run(.swapExercise(from: old, to: id))
                case .add: run(.addExercise(id))
                }
            }
        }
        .confirmationDialog("Usunąć sesję z planu?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Usuń sesję", role: .destructive) {
                if run(.removeSession) { dismiss() }
            }
            Button("Anuluj", role: .cancel) {}
        } message: {
            Text(scope == .thisAndFollowing && followingCount > 0
                 ? "Znikną też \(followingCount) kolejne takie sesje. Możesz to cofnąć na ekranie Plan."
                 : "Możesz to cofnąć na ekranie Plan.")
        }
    }

    // MARK: parts

    private var topBar: some View {
        HStack {
            SectionLabel("Edytuj sesję")
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .bold)).foregroundStyle(FormaColor.ink)
                    .frame(width: 44, height: 44).glassCapsule(interactive: true)
            }
            .accessibilityLabel("Zamknij")
        }
    }

    private func header(_ session: PlannedSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title).formaStyle(.title).foregroundStyle(FormaColor.ink)
            if let date = session.date {
                Text(Self.sentenceCase(date.formatted(.dateTime.weekday(.wide).day().month(.wide))))
                    .formaStyle(.subheadline).foregroundStyle(FormaColor.ink3)
            }
        }
    }

    private func errorBanner(_ text: String) -> some View {
        InfoBanner(systemImage: "exclamationmark.triangle.fill", tint: FormaColor.moderateText) {
            Text(text).formaStyle(.footnote).foregroundStyle(FormaColor.ink2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scopeCard: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.s) {
            SectionLabel("Zakres zmian w ćwiczeniach")
            Picker("Zakres", selection: $scope) {
                Text("Tylko ta sesja").tag(PlanEditScope.thisSession)
                Text("Ta i kolejne (\(followingCount))").tag(PlanEditScope.thisAndFollowing)
            }
            .pickerStyle(.segmented)
            Text(scope == .thisSession
                 ? "Zmiana dotyczy tylko tego dnia."
                 : "Zmiana obejmie też kolejne sesje „\(session?.title ?? "")”. Wcześniejsze zostają bez zmian.")
                .formaStyle(.footnote).foregroundStyle(FormaColor.ink3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(FormaSpacing.l).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private func exercisesCard(_ session: PlannedSession) -> some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            SectionLabel("Ćwiczenia")
            ForEach(Array(session.exercises.enumerated()), id: \.element.id) { index, item in
                exerciseRow(item, index: index, count: session.exercises.count)
                if index < session.exercises.count - 1 { Divider().overlay(FormaColor.line) }
            }
            Button {
                picking = ExercisePick(title: "Dodaj ćwiczenie", purpose: .add, excluded: Set(session.exercises.map(\.exerciseId)), timed: nil)
            } label: { Label("Dodaj ćwiczenie", systemImage: "plus").frame(maxWidth: .infinity) }
                .buttonStyle(.formaGlass)
        }
        .padding(FormaSpacing.l).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private func exerciseRow(_ item: PlannedExercise, index: Int, count: Int) -> some View {
        let exercise = store.exercise(id: item.exerciseId)
        let timed = exercise?.timed ?? false
        let unit = timed ? " s" : ""
        let step = timed ? 5 : 1
        let range = timed ? PlanLimits.seconds : PlanLimits.reps
        return VStack(alignment: .leading, spacing: FormaSpacing.s) {
            HStack {
                Text(exercise?.name ?? item.exerciseId).formaStyle(.headline).foregroundStyle(FormaColor.ink)
                Spacer()
                iconButton("chevron.up", "Wyżej", enabled: index > 0) { run(.moveExercise(item.exerciseId, toIndex: index - 1)) }
                iconButton("chevron.down", "Niżej", enabled: index < count - 1) { run(.moveExercise(item.exerciseId, toIndex: index + 1)) }
            }
            Stepper("Serie: \(item.sets)", onIncrement: { prescribe(item, sets: item.sets + 1) },
                    onDecrement: { prescribe(item, sets: item.sets - 1) })
            Stepper((timed ? "Czas od: " : "Powtórzenia od: ") + "\(item.repsMin)\(unit)",
                    onIncrement: { prescribe(item, min: min(item.repsMin + step, range.upperBound), max: max(item.repsMax, item.repsMin + step)) },
                    onDecrement: { prescribe(item, min: max(item.repsMin - step, range.lowerBound)) })
            Stepper((timed ? "Czas do: " : "Powtórzenia do: ") + "\(item.repsMax)\(unit)",
                    onIncrement: { prescribe(item, max: min(item.repsMax + step, range.upperBound)) },
                    onDecrement: { prescribe(item, min: min(item.repsMin, item.repsMax - step), max: max(item.repsMax - step, range.lowerBound)) })
            Stepper("Przerwa: \(item.restSeconds) s", onIncrement: { prescribe(item, rest: item.restSeconds + 15) },
                    onDecrement: { prescribe(item, rest: item.restSeconds - 15) })
            HStack(spacing: FormaSpacing.l) {
                Button("Zamień") {
                    picking = ExercisePick(title: "Zamień ćwiczenie", purpose: .swap(item.exerciseId),
                                           excluded: Set(session?.exercises.map(\.exerciseId) ?? []), timed: timed)
                }
                Button("Usuń", role: .destructive) { run(.removeExercise(item.exerciseId)) }
            }
            .formaStyle(.subheadline).buttonStyle(.plain).foregroundStyle(FormaColor.voltText)
        }
        .formaStyle(.body).foregroundStyle(FormaColor.ink2)
    }

    private func iconButton(_ name: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 14, weight: .bold)).frame(width: 34, height: 34)
        }
        .buttonStyle(.plain).foregroundStyle(enabled ? FormaColor.ink : FormaColor.ink3.opacity(0.4)).disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var dayCard: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.s) {
            SectionLabel("Dzień")
            DatePicker("Przenieś na", selection: $moveTo, in: days, displayedComponents: .date)
                .environment(\.locale, Locale(identifier: "pl_PL"))
            HStack(spacing: FormaSpacing.s) {
                Button { run(.moveSession(to: moveTo)) } label: { Text("Przenieś").frame(maxWidth: .infinity) }
                    .buttonStyle(.formaGlass)
                Button { run(.skip) } label: { Text("Pomiń sesję").frame(maxWidth: .infinity) }
                    .buttonStyle(.formaGlass)
            }
            Text("Przenieść można tylko na dzień bez innej sesji.").formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
        }
        .padding(FormaSpacing.l).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private var skippedCard: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            Text("Ta sesja jest pominięta").formaStyle(.headline).foregroundStyle(FormaColor.ink)
            Text("Zostaje w planie, ale nie liczy się jako dzisiejszy trening. Przywróć ją, żeby ją edytować.")
                .formaStyle(.subheadline).foregroundStyle(FormaColor.ink3)
            Button { run(.restore) } label: { Text("Przywróć sesję").frame(maxWidth: .infinity) }.buttonStyle(.formaPrimary)
        }
        .padding(FormaSpacing.l).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }

    private func removeCard(_ session: PlannedSession) -> some View {
        Button(role: .destructive) { confirmRemove = true } label: {
            Label(scope == .thisAndFollowing && followingCount > 0 ? "Usuń tę i kolejne sesje" : "Usuń sesję z planu",
                  systemImage: "trash").frame(maxWidth: .infinity)
        }
        .buttonStyle(.formaGlass)
    }

    // MARK: doing it

    @discardableResult
    private func run(_ edit: PlanEdit) -> Bool {
        switch store.edit(edit, sessionId: sessionId, scope: scope) {
        case .success:
            error = nil
            return true
        case .failure(let failure):
            error = failure.message
            return false
        }
    }

    private func prescribe(_ item: PlannedExercise, sets: Int? = nil, min: Int? = nil, max: Int? = nil, rest: Int? = nil) {
        run(.setPrescription(exerciseId: item.exerciseId, sets: sets, repsMin: min, repsMax: max, restSeconds: rest))
    }
}

struct ExercisePick: Identifiable {
    enum Purpose { case swap(String), add }
    let id = UUID()
    var title: String
    var purpose: Purpose
    var excluded: Set<String>
    var timed: Bool?
}

/// Catalog exercises that fit this person, searchable by name.
struct ExercisePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let candidates: [ExerciseItem]
    let onPick: (String) -> Void
    @State private var query = ""

    private var shown: [ExerciseItem] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? candidates : candidates.filter { $0.name.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        NavigationStack {
            List(shown) { item in
                Button {
                    onPick(item.id)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).foregroundStyle(FormaColor.ink)
                        Text(item.equipment == .none ? "Bez sprzętu" : item.equipment == .dumbbells ? "Hantle" : "Siłownia")
                            .font(.footnote).foregroundStyle(FormaColor.ink3)
                    }
                }
            }
            .overlay { if shown.isEmpty { Text("Brak pasujących ćwiczeń").foregroundStyle(FormaColor.ink3) } }
            .searchable(text: $query, prompt: "Szukaj ćwiczenia")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

/// A session of your own on a free day, built from catalog exercises.
struct AddSessionSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var day = Date()
    @State private var title = "Własna sesja"
    @State private var chosen: [String] = []
    @State private var error: String?
    @State private var query = ""

    private static let calendar = TrainingPlan.calendar

    private var days: ClosedRange<Date> {
        let today = Self.calendar.startOfDay(for: Date())
        guard let start = store.plan.startDate, let weeks = store.plan.weeks,
              let end = Self.calendar.date(byAdding: .day, value: weeks * 7 - 1, to: Self.calendar.startOfDay(for: start)),
              end >= today else { return today...today }
        return today...end
    }

    private var candidates: [ExerciseItem] {
        let all = store.exerciseCandidates(excluding: [])
        let text = query.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Dzień i nazwa") {
                    DatePicker("Dzień", selection: $day, in: days, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "pl_PL"))
                    TextField("Nazwa sesji", text: $title)
                }
                if let error { Section { Text(error).foregroundStyle(FormaColor.moderateText) } }
                Section("Ćwiczenia (\(chosen.count))") {
                    ForEach(candidates) { item in
                        Button {
                            if let index = chosen.firstIndex(of: item.id) { chosen.remove(at: index) } else { chosen.append(item.id) }
                        } label: {
                            HStack {
                                Text(item.name).foregroundStyle(FormaColor.ink)
                                Spacer()
                                if chosen.contains(item.id) { Image(systemName: "checkmark").foregroundStyle(FormaColor.voltText) }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Szukaj ćwiczenia")
            .navigationTitle("Dodaj sesję")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Dodaj") {
                        switch store.addSession(on: day, title: title, exerciseIds: chosen) {
                        case .success: dismiss()
                        case .failure(let failure): error = failure.message
                        }
                    }
                    .disabled(chosen.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }
}
