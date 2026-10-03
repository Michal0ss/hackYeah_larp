import Contracts
import Foundation

/// Why a proposed change of the plan cannot be made. The Polish text is shown to the user and told to the model.
public enum PlanChangeError: Error, Equatable, Sendable {
    case missingField(String)
    case noSuchSession
    case sessionDone
    case noSuchExercise
    case replacementNotInCatalog
    case replacementNotSuitable
    case replacementAlreadyInSession
    case incompatibleExercises
    case dayTaken
    case sameDay
    case nothingToLighten
    /// The plan is not the one the proposal was made for.
    case planChanged
    case notApplied

    public var message: String {
        switch self {
        case .missingField(let name): return "Brakuje informacji w propozycji: \(name)."
        case .noSuchSession: return "W planie nie ma sesji w tym dniu."
        case .sessionDone: return "Ta sesja jest już wykonana."
        case .noSuchExercise: return "W tej sesji nie ma takiego ćwiczenia."
        case .replacementNotInCatalog: return "Takiego ćwiczenia nie ma w katalogu."
        case .replacementNotSuitable:
            return "To ćwiczenie nie pasuje do sprzętu, poziomu albo ruchów, których użytkownik unika."
        case .replacementAlreadyInSession: return "To ćwiczenie jest już w tej sesji."
        case .incompatibleExercises:
            return "Nie da się zamienić ćwiczenia na powtórzenia na ćwiczenie na czas (albo odwrotnie)."
        case .dayTaken: return "W tym dniu jest już inna sesja."
        case .sameDay: return "Sesja już jest w tym dniu."
        case .nothingToLighten: return "Ta sesja jest już lekka: żadne ćwiczenie nie ma więcej niż dwóch serii."
        case .planChanged: return "Plan zmienił się od czasu tej propozycji."
        case .notApplied: return "Tej zmiany nie ma w planie, więc nie ma czego cofać."
        }
    }
}

/// Builds, applies and undoes proposed changes of the plan. Pure and deterministic: no model, no I/O.
///
/// Every check is done twice on purpose: when the coach proposes (so the user only sees possible changes) and again
/// when the user accepts (the plan may have changed since). Only catalog exercises that fit the person are accepted.
public struct PlanChanger: Sendable {
    public var catalog: [ExerciseItem]
    public var profile: UserProfile

    public init(catalog: [ExerciseItem], profile: UserProfile) {
        self.catalog = catalog
        self.profile = profile
    }

    // MARK: propose

    /// A pending proposal for what the model asked, or the reason it cannot be done.
    public func propose(kind: PlanChangeKind, weekday: Int?, exerciseId: String?, replacementExerciseId: String?,
                        newWeekday: Int?, reason: String?, in plan: TrainingPlan) throws -> PlanChangeProposal {
        guard let weekday else { throw PlanChangeError.missingField("dzień sesji") }
        guard let session = plan.sessions.first(where: { $0.weekday == weekday }) else { throw PlanChangeError.noSuchSession }
        guard session.status != .done else { throw PlanChangeError.sessionDone }

        var proposal = PlanChangeProposal(kind: kind, sessionId: session.id, sessionTitle: session.title, weekday: weekday,
                                          summary: "", reason: Self.cleanReason(reason))
        switch kind {
        case .swapExercise:
            guard let exerciseId else { throw PlanChangeError.missingField("ćwiczenie do zamiany") }
            guard let replacementExerciseId else { throw PlanChangeError.missingField("ćwiczenie zastępcze") }
            proposal.exerciseId = exerciseId
            proposal.replacementExerciseId = replacementExerciseId
        case .lighterSession:
            break
        case .moveSession:
            guard let newWeekday else { throw PlanChangeError.missingField("nowy dzień") }
            proposal.newWeekday = newWeekday
        }
        // Dry run: the same code that will run on "Zastosuj" decides whether it is possible and what it says.
        let result = try change(proposal, in: plan)
        proposal.summary = result.summary
        return proposal
    }

    // MARK: apply and undo

    /// The plan with the change made, and the proposal marked as applied (with the session before and after).
    public func apply(_ proposal: PlanChangeProposal, to plan: TrainingPlan) throws -> (plan: TrainingPlan, proposal: PlanChangeProposal) {
        guard proposal.status == .pending else { throw PlanChangeError.planChanged }
        let result = try change(proposal, in: plan)
        var newPlan = plan
        guard let index = newPlan.sessions.firstIndex(where: { $0.id == proposal.sessionId }) else {
            throw PlanChangeError.noSuchSession
        }
        let before = newPlan.sessions[index]
        newPlan.sessions[index] = result.session
        var done = proposal
        done.status = .applied
        done.summary = result.summary
        done.before = before
        done.after = result.session
        return (newPlan, done)
    }

    /// Puts the session back as it was, but only if nothing else changed it since.
    public func undo(_ proposal: PlanChangeProposal, in plan: TrainingPlan) throws -> (plan: TrainingPlan, proposal: PlanChangeProposal) {
        guard proposal.status == .applied, let before = proposal.before, let after = proposal.after else {
            throw PlanChangeError.notApplied
        }
        guard let index = plan.sessions.firstIndex(where: { $0.id == proposal.sessionId }), plan.sessions[index] == after else {
            throw PlanChangeError.planChanged
        }
        // Moving back needs the old day to be free again.
        if plan.sessions.contains(where: { $0.id != before.id && $0.weekday == before.weekday }) {
            throw PlanChangeError.dayTaken
        }
        var newPlan = plan
        newPlan.sessions[index] = before
        var undone = proposal
        undone.status = .undone
        return (newPlan, undone)
    }

    // MARK: the change itself

    private func change(_ proposal: PlanChangeProposal, in plan: TrainingPlan) throws -> (session: PlannedSession, summary: String) {
        guard let session = plan.sessions.first(where: { $0.id == proposal.sessionId }) else { throw PlanChangeError.noSuchSession }
        guard session.status != .done else { throw PlanChangeError.sessionDone }
        let day = Self.dayName(session.weekday)
        switch proposal.kind {
        case .swapExercise: return try swap(proposal, session, day)
        case .lighterSession: return try lighter(session, day)
        case .moveSession: return try move(proposal, session, plan)
        }
    }

    private func swap(_ proposal: PlanChangeProposal, _ session: PlannedSession, _ day: String) throws -> (PlannedSession, String) {
        guard let oldId = proposal.exerciseId, let index = session.exercises.firstIndex(where: { $0.exerciseId == oldId }) else {
            throw PlanChangeError.noSuchExercise
        }
        guard let newId = proposal.replacementExerciseId, let replacement = catalog.first(where: { $0.id == newId }) else {
            throw PlanChangeError.replacementNotInCatalog
        }
        guard !session.exercises.contains(where: { $0.exerciseId == newId }) else { throw PlanChangeError.replacementAlreadyInSession }
        guard isSuitable(replacement) else { throw PlanChangeError.replacementNotSuitable }
        let old = catalog.first { $0.id == oldId }
        // Sets and a range of reps fit exercises counted in the same unit only (reps vs seconds).
        guard (old?.timed ?? false) == (replacement.timed ?? false) else { throw PlanChangeError.incompatibleExercises }

        var changed = session
        changed.exercises[index].exerciseId = newId
        changed.exercises[index].tempo = replacement.defaultTempo ?? session.exercises[index].tempo
        let summary = "Zamień „\(old?.name ?? oldId)” na „\(replacement.name)” w sesji „\(session.title)” (\(day))"
        return (changed, summary)
    }

    private func lighter(_ session: PlannedSession, _ day: String) throws -> (PlannedSession, String) {
        var changed = session
        var lightened = 0
        for index in changed.exercises.indices where changed.exercises[index].sets > 2 {
            changed.exercises[index].sets -= 1
            lightened += 1
        }
        guard lightened > 0 else { throw PlanChangeError.nothingToLighten }
        let summary = "Lżejsza sesja „\(session.title)” (\(day)): o jedną serię mniej w \(lightened) \(Self.exercisesWord(lightened))"
        return (changed, summary)
    }

    private func move(_ proposal: PlanChangeProposal, _ session: PlannedSession, _ plan: TrainingPlan) throws -> (PlannedSession, String) {
        guard let target = proposal.newWeekday, (1...7).contains(target) else { throw PlanChangeError.missingField("nowy dzień") }
        guard target != session.weekday else { throw PlanChangeError.sameDay }
        guard !plan.sessions.contains(where: { $0.weekday == target }) else { throw PlanChangeError.dayTaken }
        var changed = session
        changed.weekday = target
        let summary = "Przenieś sesję „\(session.title)” z \(Self.dayFrom(session.weekday)) na \(Self.dayTo(target))"
        return (changed, summary)
    }

    // MARK: suitability

    private static func rank(_ equipment: Equipment) -> Int {
        switch equipment {
        case .none: return 0
        case .dumbbells: return 1
        case .gym: return 2
        }
    }

    /// Equipment, level and the movements the person avoids, as in the server's `allowed_exercises`. An easy start
    /// counts as a beginner. The server also applies the level a goal forces; it checks every replacement before the
    /// coach can propose it, so this is the second, weaker line of defence.
    func isSuitable(_ exercise: ExerciseItem) -> Bool {
        guard Self.rank(exercise.equipment) <= Self.rank(profile.equipment) else { return false }
        let level: TrainingLevel = profile.easyStart ? .beginner : profile.level
        if exercise.level == .intermediate, level == .beginner { return false }
        if let tags = exercise.movementTags, !Set(tags).isDisjoint(with: profile.avoidTags) { return false }
        return true
    }

    // MARK: Polish wording

    private static let names = ["poniedziałek", "wtorek", "środę", "czwartek", "piątek", "sobotę", "niedzielę"]
    private static let from = ["poniedziałku", "wtorku", "środy", "czwartku", "piątku", "soboty", "niedzieli"]
    private static let nominative = ["poniedziałek", "wtorek", "środa", "czwartek", "piątek", "sobota", "niedziela"]

    static func dayName(_ weekday: Int) -> String { nominative[(weekday - 1) % 7] }
    static func dayFrom(_ weekday: Int) -> String { from[(weekday - 1) % 7] }
    static func dayTo(_ weekday: Int) -> String { names[(weekday - 1) % 7] }

    private static func exercisesWord(_ n: Int) -> String {
        if n == 1 { return "ćwiczeniu" }
        return "ćwiczeniach"
    }

    private static func cleanReason(_ text: String?) -> String? {
        guard let text else { return nil }
        let line = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : String(line.prefix(160))
    }
}
