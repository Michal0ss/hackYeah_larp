import Contracts
import Foundation

/// How far an edit reaches in a plan that has dates.
public enum PlanEditScope: String, Codable, Sendable, CaseIterable {
    /// Only the session you are looking at.
    case thisSession
    /// This session and every later session with the same title that is not finished or skipped (the same day of every
    /// following week). The earlier ones stay as they were.
    case thisAndFollowing
}

/// One change the user makes to a session by hand.
public enum PlanEdit: Equatable, Sendable {
    /// Replace an exercise with another one from the catalog.
    case swapExercise(from: String, to: String)
    /// Sets, reps (or seconds) and rest of one exercise; a nil value stays as it is.
    case setPrescription(exerciseId: String, sets: Int?, repsMin: Int?, repsMax: Int?, restSeconds: Int?)
    /// Add an exercise at the end, with the usual prescription of the session's other exercises.
    case addExercise(String)
    case removeExercise(String)
    /// Put an exercise at a position (0 = first).
    case moveExercise(String, toIndex: Int)
    /// Move the session to another day (this session only).
    case moveSession(to: Date)
    /// Leave the session out; it can be restored (this session only).
    case skip
    case restore
    /// Take the session out of the plan for good.
    case removeSession
}

public struct PlanEditResult: Equatable, Sendable {
    public var plan: TrainingPlan
    /// The sessions that changed, as they were before, so the screen can say how many and undo is easy.
    public var changedSessionIds: [UUID]
    /// Polish, e.g. "Zmieniono 4 sesje".
    public var summary: String
}

/// Edits of the plan made by the user. Pure and deterministic, with the same limits and the same equipment, level and
/// avoided-movement checks as the coach's proposals (`PlanChanger`): the catalog is the only source of exercises.
public struct PlanEditor: Sendable {
    private let changer: PlanChanger
    private var catalog: [ExerciseItem] { changer.catalog }
    private var calendar: Calendar { changer.calendar }

    public init(catalog: [ExerciseItem], profile: UserProfile, calendar: Calendar = TrainingPlan.calendar,
                now: @escaping @Sendable () -> Date = { Date() }) {
        changer = PlanChanger(catalog: catalog, profile: profile, calendar: calendar, now: now)
    }

    /// The exercises this person can add or swap in, by name. `timed` limits them to exercises counted in seconds
    /// (true) or in reps (false), which is what a swap needs.
    public func candidates(excluding ids: Set<String>, timed: Bool? = nil) -> [ExerciseItem] {
        catalog.filter { !ids.contains($0.id) && changer.isSuitable($0) && (timed == nil || ($0.timed ?? false) == timed) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    // MARK: edits

    public func apply(_ edit: PlanEdit, to sessionId: UUID, scope: PlanEditScope = .thisSession,
                      in plan: TrainingPlan) throws -> PlanEditResult {
        guard let session = plan.sessions.first(where: { $0.id == sessionId }) else { throw PlanChangeError.noSuchSession }
        try requireEditable(session, allowSkipped: edit == .restore)

        var newPlan = plan
        var changed: [UUID] = []
        switch edit {
        case .moveSession(let day):
            let moved = try move(session, to: day, in: plan)
            replace(moved, in: &newPlan)
            changed = [moved.id]
        case .skip:
            var skipped = session
            skipped.status = .skipped
            replace(skipped, in: &newPlan)
            changed = [skipped.id]
        case .restore:
            guard session.status == .skipped else { throw PlanChangeError.notApplied }
            var back = session
            back.status = .planned
            replace(back, in: &newPlan)
            changed = [back.id]
        case .removeSession:
            let targets = targets(of: session, scope: scope, in: plan)
            newPlan.sessions.removeAll { target in targets.contains { $0.id == target.id } }
            changed = targets.map(\.id)
        default:
            // Validate on the session itself first, so a bad edit fails with a clear reason instead of changing
            // some of the following sessions only.
            _ = try edited(session, with: edit)
            for target in targets(of: session, scope: scope, in: plan) {
                guard let result = try? edited(target, with: edit), result != target else { continue }
                replace(result, in: &newPlan)
                changed.append(target.id)
            }
        }
        guard !changed.isEmpty else { throw PlanChangeError.notApplied }
        return PlanEditResult(plan: newPlan, changedSessionIds: changed, summary: Self.summary(for: edit, count: changed.count))
    }

    /// Adds a session of your own on a free day. It must have exercises from the catalog that fit you.
    public func addSession(on day: Date, title: String, exerciseIds: [String], in plan: TrainingPlan) throws -> PlanEditResult {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else { throw PlanChangeError.invalidValue("nazwa sesji") }
        guard !exerciseIds.isEmpty else { throw PlanChangeError.lastExercise }
        guard exerciseIds.count <= PlanLimits.maxExercises else { throw PlanChangeError.tooManyExercises }
        let date = calendar.startOfDay(for: day)
        try requireFreeDay(date, excluding: nil, in: plan)
        let exercises = try exerciseIds.map { id -> PlannedExercise in
            guard let item = catalog.first(where: { $0.id == id }) else { throw PlanChangeError.replacementNotInCatalog }
            guard changer.isSuitable(item) else { throw PlanChangeError.replacementNotSuitable }
            return Self.defaultPrescription(for: item, like: [])
        }
        let session = PlannedSession(weekday: TrainingPlan.isoWeekday(of: date, calendar: calendar), title: name,
                                     exercises: exercises, date: date)
        var newPlan = plan
        newPlan.sessions.append(session)
        return PlanEditResult(plan: newPlan, changedSessionIds: [session.id], summary: "Dodano sesję „\(name)”")
    }

    // MARK: one session

    private func edited(_ session: PlannedSession, with edit: PlanEdit) throws -> PlannedSession {
        var result = session
        switch edit {
        case .swapExercise(let from, let to):
            guard let index = result.exercises.firstIndex(where: { $0.exerciseId == from }) else { throw PlanChangeError.noSuchExercise }
            guard let replacement = catalog.first(where: { $0.id == to }) else { throw PlanChangeError.replacementNotInCatalog }
            guard !result.exercises.contains(where: { $0.exerciseId == to }) else { throw PlanChangeError.replacementAlreadyInSession }
            guard changer.isSuitable(replacement) else { throw PlanChangeError.replacementNotSuitable }
            let old = catalog.first { $0.id == from }
            guard (old?.timed ?? false) == (replacement.timed ?? false) else { throw PlanChangeError.incompatibleExercises }
            result.exercises[index].exerciseId = to
            result.exercises[index].tempo = replacement.defaultTempo ?? result.exercises[index].tempo
        case .setPrescription(let id, let sets, let repsMin, let repsMax, let rest):
            guard let index = result.exercises.firstIndex(where: { $0.exerciseId == id }) else { throw PlanChangeError.noSuchExercise }
            var item = result.exercises[index]
            let timed = catalog.first { $0.id == id }?.timed ?? false
            if let sets { item.sets = sets }
            if let repsMin { item.repsMin = repsMin }
            if let repsMax { item.repsMax = repsMax }
            if let rest { item.restSeconds = rest }
            guard PlanLimits.sets.contains(item.sets) else { throw PlanChangeError.invalidValue("liczba serii") }
            let range = timed ? PlanLimits.seconds : PlanLimits.reps
            guard range.contains(item.repsMin), range.contains(item.repsMax), item.repsMin <= item.repsMax else {
                throw PlanChangeError.invalidValue(timed ? "czas ćwiczenia" : "liczba powtórzeń")
            }
            guard PlanLimits.rest.contains(item.restSeconds) else { throw PlanChangeError.invalidValue("przerwa") }
            result.exercises[index] = item
        case .addExercise(let id):
            guard let item = catalog.first(where: { $0.id == id }) else { throw PlanChangeError.replacementNotInCatalog }
            guard !result.exercises.contains(where: { $0.exerciseId == id }) else { throw PlanChangeError.replacementAlreadyInSession }
            guard result.exercises.count < PlanLimits.maxExercises else { throw PlanChangeError.tooManyExercises }
            guard changer.isSuitable(item) else { throw PlanChangeError.replacementNotSuitable }
            result.exercises.append(Self.defaultPrescription(for: item, like: result.exercises))
        case .removeExercise(let id):
            guard let index = result.exercises.firstIndex(where: { $0.exerciseId == id }) else { throw PlanChangeError.noSuchExercise }
            guard result.exercises.count > 1 else { throw PlanChangeError.lastExercise }
            result.exercises.remove(at: index)
        case .moveExercise(let id, let target):
            guard let index = result.exercises.firstIndex(where: { $0.exerciseId == id }) else { throw PlanChangeError.noSuchExercise }
            let item = result.exercises.remove(at: index)
            result.exercises.insert(item, at: min(max(target, 0), result.exercises.count))
        case .moveSession, .skip, .restore, .removeSession:
            break
        }
        return result
    }

    private func move(_ session: PlannedSession, to day: Date, in plan: TrainingPlan) throws -> PlannedSession {
        let target = calendar.startOfDay(for: day)
        try requireFreeDay(target, excluding: session.id, in: plan)
        var moved = session
        moved.date = target
        moved.weekday = TrainingPlan.isoWeekday(of: target, calendar: calendar)
        return moved
    }

    // MARK: checks

    private func requireEditable(_ session: PlannedSession, allowSkipped: Bool) throws {
        guard session.status != .done else { throw PlanChangeError.sessionDone }
        if session.status == .skipped, !allowSkipped { throw PlanChangeError.sessionSkipped }
    }

    /// A day from today to the last day of the plan with no other session.
    func requireFreeDay(_ day: Date, excluding id: UUID?, in plan: TrainingPlan) throws {
        guard plan.isDated else { throw PlanChangeError.outsidePlan }
        let today = calendar.startOfDay(for: changer.now())
        guard day >= today else { throw PlanChangeError.outsidePlan }
        if let start = plan.startDate, let weeks = plan.weeks,
           let end = calendar.date(byAdding: .day, value: weeks * 7, to: calendar.startOfDay(for: start)), day >= end {
            throw PlanChangeError.outsidePlan
        }
        if plan.sessions.contains(where: { $0.id != id && $0.date.map { calendar.isDate($0, inSameDayAs: day) } ?? false }) {
            throw PlanChangeError.dayTaken
        }
    }

    /// The session, and with `thisAndFollowing` its later namesakes that can still change.
    private func targets(of session: PlannedSession, scope: PlanEditScope, in plan: TrainingPlan) -> [PlannedSession] {
        guard scope == .thisAndFollowing, let date = session.date else { return [session] }
        return plan.chronological.filter {
            $0.id == session.id
                || ($0.title == session.title && ($0.date ?? .distantPast) > date && $0.status != .done && $0.status != .skipped)
        }
    }

    private func replace(_ session: PlannedSession, in plan: inout TrainingPlan) {
        if let index = plan.sessions.firstIndex(where: { $0.id == session.id }) { plan.sessions[index] = session }
    }

    // MARK: defaults and wording

    /// What a new exercise gets: the sets and rest of the session's other exercises, reps by the exercise's kind.
    static func defaultPrescription(for item: ExerciseItem, like others: [PlannedExercise]) -> PlannedExercise {
        let sets = others.first?.sets ?? 3
        let timed = item.timed ?? false
        return PlannedExercise(exerciseId: item.id, sets: timed ? min(sets, 3) : sets, repsMin: timed ? 30 : 8,
                               repsMax: timed ? 45 : 12, restSeconds: others.first?.restSeconds ?? 90, tempo: item.defaultTempo)
    }

    private static func summary(for edit: PlanEdit, count: Int) -> String {
        let what: String
        switch edit {
        case .swapExercise: what = "Zamieniono ćwiczenie"
        case .setPrescription: what = "Zmieniono serie i powtórzenia"
        case .addExercise: what = "Dodano ćwiczenie"
        case .removeExercise: what = "Usunięto ćwiczenie"
        case .moveExercise: what = "Zmieniono kolejność"
        case .moveSession: what = "Przeniesiono sesję"
        case .skip: what = "Pominięto sesję"
        case .restore: what = "Przywrócono sesję"
        case .removeSession: what = count == 1 ? "Usunięto sesję" : "Usunięto \(count) sesje"
        }
        return count > 1 && edit != .removeSession ? "\(what) w \(count) sesjach" : what
    }
}
