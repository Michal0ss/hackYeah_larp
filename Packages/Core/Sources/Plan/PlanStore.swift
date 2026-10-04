import Contracts
import Foundation

/// A session the user finished. Kept apart from the plan so that the finished sessions survive when the plan is
/// replaced (a rebuilt plan has new sessions, the history of what was done stays).
public struct SessionCompletion: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// `PlannedSession.id` that was finished.
    public var sessionId: UUID
    public var date: Date
    public var completedSets: Int?
    public var plannedSets: Int?

    public init(id: UUID = UUID(), sessionId: UUID, date: Date, completedSets: Int? = nil, plannedSets: Int? = nil) {
        self.id = id
        self.sessionId = sessionId
        self.date = date
        self.completedSets = completedSets
        self.plannedSets = plannedSets
    }
}

/// The user's plan on the phone: the dated plan itself (every session has its day), and which sessions were finished.
///
/// - The saved plan never carries `done`: finishing a session is a record in the log, and `resolved` returns the plan
///   with `done` set from it. Sessions are per date, so a finished session stays finished.
/// - First launch after the update: the plan is taken from the onboarding file (`bootstrap`) and written here. A plan
///   without dates (saved by an older version) is laid out on the calendar from today.
/// - A missing or unreadable file never crashes: it falls back to the bootstrap plan, and a broken file is kept
///   aside as `*.corrupt.json`.
///
/// Readable without `await` (the screens ask it while drawing), hence a lock instead of an actor.
public final class PlanStore: PlanProviding, @unchecked Sendable {
    /// Older completions are dropped.
    public static let maxCompletions = 400

    private struct Stored: Codable {
        var plan: TrainingPlan?
        var completions: [SessionCompletion] = []
    }

    private let lock = NSLock()
    private var stored = Stored()
    private let fileURL: URL?
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    /// Called after every change of the saved data (from whatever thread made it), so the screens can refresh. Set
    /// once at start-up.
    public var onChange: (@Sendable () -> Void)?

    /// - Parameters:
    ///   - fileURL: nil keeps everything in memory (tests, previews).
    ///   - bootstrap: the plan to start from when nothing is saved yet (the one from onboarding).
    public init(fileURL: URL?, calendar: Calendar = Calendar(identifier: .iso8601),
                now: @escaping @Sendable () -> Date = { Date() }, bootstrap: @Sendable () -> TrainingPlan? = { nil }) {
        self.fileURL = fileURL
        self.calendar = calendar
        self.now = now
        if let loaded = Self.read(fileURL) {
            stored = loaded
        }
        var changed = false
        if stored.plan == nil, let first = bootstrap() {
            stored.plan = Self.normalized(first)
            changed = true
        }
        if let plan = stored.plan, !plan.isDated {
            stored.plan = PlanScheduler.schedule(plan, startingOn: now(), calendar: calendar)
            changed = true
        }
        if changed { persist() }
    }

    /// `Application Support/Forma/plan.json`.
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Forma", isDirectory: true).appendingPathComponent("plan.json")
    }

    // MARK: the plan

    /// The plan as saved: dated sessions, no `done`.
    public var templatePlan: TrainingPlan? {
        lock.lock(); defer { lock.unlock() }
        return stored.plan
    }

    /// Replaces the plan. Returns whether it reached the disk (it is kept in memory either way).
    @discardableResult
    public func save(_ plan: TrainingPlan) -> Bool {
        defer { onChange?() }
        lock.lock(); defer { lock.unlock() }
        stored.plan = Self.normalized(plan.isDated ? plan : PlanScheduler.schedule(plan, startingOn: now(), calendar: calendar))
        return persist()
    }

    /// Forgets the plan and the completions (the user deleted all data).
    public func clear() {
        lock.lock()
        stored = Stored()
        lock.unlock()
        onChange?()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    // MARK: completions

    /// Marks a session finished on `date` (default: now). Marking the same session again replaces the earlier
    /// entry. Returns whether it reached the disk.
    @discardableResult
    public func recordCompletion(sessionId: UUID, date: Date? = nil, completedSets: Int? = nil,
                                 plannedSets: Int? = nil) -> Bool {
        defer { onChange?() }
        lock.lock(); defer { lock.unlock() }
        stored.completions.removeAll { $0.sessionId == sessionId }
        stored.completions.insert(SessionCompletion(sessionId: sessionId, date: date ?? now(), completedSets: completedSets,
                                                    plannedSets: plannedSets), at: 0)
        if stored.completions.count > Self.maxCompletions {
            stored.completions.removeLast(stored.completions.count - Self.maxCompletions)
        }
        return persist()
    }

    /// Adds sessions that were finished on another phone (the account restores them). A session that is already marked
    /// done here keeps the entry it has. Returns how many were added.
    @discardableResult
    public func restore(completions restored: [SessionCompletion]) -> Int {
        defer { onChange?() }
        lock.lock(); defer { lock.unlock() }
        let known = Set(stored.completions.map(\.sessionId))
        let added = restored.filter { !known.contains($0.sessionId) }
        guard !added.isEmpty else { return 0 }
        stored.completions = (stored.completions + added).sorted { $0.date > $1.date }
        if stored.completions.count > Self.maxCompletions {
            stored.completions.removeLast(stored.completions.count - Self.maxCompletions)
        }
        persist()
        return added.count
    }

    /// Takes back "done" for a session (the user marked it by mistake).
    @discardableResult
    public func removeCompletion(sessionId: UUID) -> Bool {
        defer { onChange?() }
        lock.lock(); defer { lock.unlock() }
        stored.completions.removeAll { $0.sessionId == sessionId }
        return persist()
    }

    /// Newest first.
    public var completions: [SessionCompletion] {
        lock.lock(); defer { lock.unlock() }
        return stored.completions
    }

    public func completedSessionIds() -> Set<UUID> {
        lock.lock(); defer { lock.unlock() }
        return Set(stored.completions.map(\.sessionId))
    }

    // MARK: reading

    /// The saved plan with `done` on the finished sessions.
    public func resolvedPlan() -> TrainingPlan? {
        templatePlan.map(resolved)
    }

    /// Any plan (for example the one the screens hold) with `done` on the finished sessions.
    public func resolved(_ plan: TrainingPlan) -> TrainingPlan {
        let finished = completedSessionIds()
        var result = plan
        for index in result.sessions.indices where finished.contains(result.sessions[index].id) {
            result.sessions[index].status = .done
        }
        return result
    }

    // MARK: PlanProviding

    public func currentPlan() async -> TrainingPlan? { resolvedPlan() }

    /// Today's session, or the next planned one (a finished session of today is still returned, with `done`).
    /// Nil when there is none left: the plan has run out.
    public func todaySession() async -> PlannedSession? {
        resolvedPlan()?.sessionOnOrAfter(now(), calendar: calendar)
    }

    // MARK: helpers

    /// The plan never stores a finished session: that lives in the completions.
    private static func normalized(_ plan: TrainingPlan) -> TrainingPlan {
        var result = plan
        for index in result.sessions.indices where result.sessions[index].status == .done {
            result.sessions[index].status = .planned
        }
        return result
    }

    // Full-precision dates (the default coding), so a saved plan loads back identical.
    private static func read(_ fileURL: URL?) -> Stored? {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL), let loaded = try? JSONDecoder().decode(Stored.self, from: data) else {
            let aside = fileURL.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            return nil
        }
        return loaded
    }

    @discardableResult
    private func persist() -> Bool {
        guard let fileURL else { return true }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(stored).write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
