import Contracts
import Foundation

/// A session the user finished on a given day. Kept apart from the plan: the plan is a pattern of one week
/// (weekday 1...7, no dates) that repeats, so "done" has to be tied to a date, or Monday's session would still
/// count as done the next Monday.
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

/// The user's weekly plan on the phone: the plan itself, and which sessions were finished in which week.
///
/// - The saved plan never carries `done`: a status of one week must not leak into the next. `resolved...` returns
///   the plan with `done` set for the sessions finished in the week of the given day.
/// - First launch after the update: the plan is taken from the onboarding file (`bootstrap`) and written here.
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
        if stored.plan == nil, let first = bootstrap() {
            stored.plan = Self.normalized(first)
            persist()
        }
    }

    /// `Application Support/Forma/plan.json`.
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Forma", isDirectory: true).appendingPathComponent("plan.json")
    }

    // MARK: the plan

    /// The plan as saved: the weekly pattern, no `done`.
    public var templatePlan: TrainingPlan? {
        lock.lock(); defer { lock.unlock() }
        return stored.plan
    }

    /// Replaces the plan. Returns whether it reached the disk (it is kept in memory either way).
    @discardableResult
    public func save(_ plan: TrainingPlan) -> Bool {
        lock.lock(); defer { lock.unlock() }
        stored.plan = Self.normalized(plan)
        return persist()
    }

    /// Forgets the plan and the completions (the user deleted all data).
    public func clear() {
        lock.lock()
        stored = Stored()
        lock.unlock()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    // MARK: completions

    /// Marks a session finished on `date`. Marking the same session again in the same week replaces the earlier
    /// entry. Returns whether it reached the disk.
    @discardableResult
    public func recordCompletion(sessionId: UUID, date: Date? = nil, completedSets: Int? = nil,
                                 plannedSets: Int? = nil) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let day = date ?? now()
        stored.completions.removeAll { $0.sessionId == sessionId && sameWeek($0.date, day) }
        stored.completions.insert(SessionCompletion(sessionId: sessionId, date: day, completedSets: completedSets,
                                                    plannedSets: plannedSets), at: 0)
        if stored.completions.count > Self.maxCompletions {
            stored.completions.removeLast(stored.completions.count - Self.maxCompletions)
        }
        return persist()
    }

    /// Takes back "done" for a session in the week of `date` (the user marked it by mistake).
    @discardableResult
    public func removeCompletion(sessionId: UUID, weekOf date: Date? = nil) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let day = date ?? now()
        stored.completions.removeAll { $0.sessionId == sessionId && sameWeek($0.date, day) }
        return persist()
    }

    /// Newest first.
    public var completions: [SessionCompletion] {
        lock.lock(); defer { lock.unlock() }
        return stored.completions
    }

    /// Sessions finished in the week of `date` (default: this week).
    public func completedSessionIds(weekOf date: Date? = nil) -> Set<UUID> {
        lock.lock(); defer { lock.unlock() }
        let day = date ?? now()
        return Set(stored.completions.filter { sameWeek($0.date, day) }.map(\.sessionId))
    }

    // MARK: reading

    /// The saved plan with `done` on the sessions finished in the week of `date`.
    public func resolvedPlan(on date: Date? = nil) -> TrainingPlan? {
        templatePlan.map { resolved($0, on: date) }
    }

    /// Any plan (for example the one the screens hold) with `done` for the sessions finished that week.
    public func resolved(_ plan: TrainingPlan, on date: Date? = nil) -> TrainingPlan {
        let finished = completedSessionIds(weekOf: date)
        var result = plan
        for index in result.sessions.indices where finished.contains(result.sessions[index].id) {
            result.sessions[index].status = .done
        }
        return result
    }

    // MARK: PlanProviding

    public func currentPlan() async -> TrainingPlan? { resolvedPlan() }

    /// Today's session, or the next planned one (a finished session of today is still returned, with `done`).
    public func todaySession() async -> PlannedSession? {
        guard let plan = resolvedPlan() else { return nil }
        let weekday = calendar.component(.weekday, from: now())
        let today = weekday == 1 ? 7 : weekday - 1  // Calendar: 1 = Sunday. Plan: 1 = Monday.
        let sessions = plan.sessions.sorted { $0.weekday < $1.weekday }
        return sessions.first { $0.weekday == today } ?? sessions.first { $0.weekday > today } ?? sessions.first
    }

    // MARK: helpers

    private func sameWeek(_ a: Date, _ b: Date) -> Bool {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: b) else { return false }
        return week.contains(a)
    }

    /// The pattern never stores a finished session: that lives in the completions.
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
