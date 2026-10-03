import Contracts
import Foundation

/// Where the numbers of a set came from.
public enum LoggedSetSource: String, Codable, Sendable {
    /// Counted by the live coach (camera). The user may still correct the reps and add a weight.
    case live
    /// Typed by the user (exercises without analysis, or a set added later).
    case manual
}

/// Limits of what can be typed in.
public enum LoggedSetLimits {
    public static let reps = 0...200
    public static let seconds = 0...3600
    public static let weightKg = 0.0...500.0
}

/// One set the user did: the numbers, and a weight only when they entered one.
public struct LoggedSet: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// `PlannedSession.id` the set belongs to.
    public var sessionId: UUID
    /// Catalog id of the exercise.
    public var exerciseId: String
    /// 1-based number of the set within the exercise.
    public var setIndex: Int
    public var date: Date
    /// Repetitions, for exercises counted in reps.
    public var reps: Int?
    /// Seconds, for exercises counted in time (a plank).
    public var seconds: Int?
    /// Kilograms, nil when no weight was entered (body weight, or the user did not say).
    public var weightKg: Double?
    public var source: LoggedSetSource
    /// True when the user changed what the camera counted or what they typed earlier.
    public var isEdited: Bool
    /// `SetSummary.id` of the live set this comes from, to find its technique and tempo results.
    public var liveSetId: UUID?

    public init(id: UUID = UUID(), sessionId: UUID, exerciseId: String, setIndex: Int, date: Date = Date(),
                reps: Int? = nil, seconds: Int? = nil, weightKg: Double? = nil, source: LoggedSetSource = .manual,
                isEdited: Bool = false, liveSetId: UUID? = nil) {
        self.id = id
        self.sessionId = sessionId
        self.exerciseId = exerciseId
        self.setIndex = setIndex
        self.date = date
        self.reps = reps.map { min(max($0, LoggedSetLimits.reps.lowerBound), LoggedSetLimits.reps.upperBound) }
        self.seconds = seconds.map { min(max($0, LoggedSetLimits.seconds.lowerBound), LoggedSetLimits.seconds.upperBound) }
        self.weightKg = Self.clean(weight: weightKg)
        self.source = source
        self.isEdited = isEdited
        self.liveSetId = liveSetId
    }

    /// A weight of 0 or less means "none"; the rest is limited and rounded to 0.25 kg.
    static func clean(weight: Double?) -> Double? {
        guard let weight, weight > 0 else { return nil }
        let limited = min(weight, LoggedSetLimits.weightKg.upperBound)
        return (limited * 4).rounded() / 4
    }
}

/// The sets the user did, kept on the phone as a JSON file (`training-log.json`). Writes never crash: a broken file is
/// moved aside (`*.corrupt.json`) and the log starts empty. Readable without `await`, hence a lock.
public final class TrainingLogStore: @unchecked Sendable {
    /// Older sets are dropped.
    public static let maxSets = 3000

    private let lock = NSLock()
    private var stored: [LoggedSet] = []
    private let fileURL: URL?

    /// - Parameter fileURL: nil keeps the log in memory (tests, previews).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let loaded = Self.read(fileURL) { stored = loaded }
    }

    /// `Application Support/Forma/training-log.json`.
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Forma", isDirectory: true).appendingPathComponent("training-log.json")
    }

    // MARK: writing

    /// Saves a set. The same set of the same exercise in the same session (same `setIndex`) is replaced, so doing it
    /// again does not leave two entries. Returns whether it reached the disk.
    @discardableResult
    public func record(_ set: LoggedSet) -> Bool {
        lock.lock(); defer { lock.unlock() }
        stored.removeAll { $0.id == set.id || ($0.sessionId == set.sessionId && $0.exerciseId == set.exerciseId && $0.setIndex == set.setIndex) }
        stored.insert(set, at: 0)
        if stored.count > Self.maxSets { stored.removeLast(stored.count - Self.maxSets) }
        return persist()
    }

    /// Changes the numbers of a set; what is left nil stays as it is. Marks the set as edited.
    @discardableResult
    public func edit(_ id: UUID, reps: Int? = nil, seconds: Int? = nil, weightKg: Double?? = nil) -> LoggedSet? {
        lock.lock(); defer { lock.unlock() }
        guard let index = stored.firstIndex(where: { $0.id == id }) else { return nil }
        var set = stored[index]
        if let reps { set.reps = min(max(reps, LoggedSetLimits.reps.lowerBound), LoggedSetLimits.reps.upperBound) }
        if let seconds { set.seconds = min(max(seconds, LoggedSetLimits.seconds.lowerBound), LoggedSetLimits.seconds.upperBound) }
        // `weightKg: .some(nil)` removes the weight, `.none` leaves it.
        if let weightKg { set.weightKg = LoggedSet.clean(weight: weightKg) }
        set.isEdited = set != stored[index] || set.isEdited
        stored[index] = set
        persist()
        return set
    }

    @discardableResult
    public func remove(_ id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        stored.removeAll { $0.id == id }
        return persist()
    }

    /// Removes every set of one session (the user repeats the workout from scratch). Returns how many were removed.
    @discardableResult
    public func removeSets(forSession sessionId: UUID) -> Int {
        lock.lock(); defer { lock.unlock() }
        let before = stored.count
        stored.removeAll { $0.sessionId == sessionId }
        if stored.count != before { persist() }
        return before - stored.count
    }

    /// Forgets everything (the user deleted all data).
    public func clear() {
        lock.lock()
        stored = []
        lock.unlock()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    // MARK: reading

    /// Newest first.
    public var sets: [LoggedSet] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    /// The sets of one session, by exercise order of first appearance is the caller's business: here by set number.
    public func sets(forSession id: UUID) -> [LoggedSet] {
        sets.filter { $0.sessionId == id }.sorted { ($0.date, $0.setIndex) < ($1.date, $1.setIndex) }
    }

    /// The weight used last time for an exercise, to prefill the next one.
    public func lastWeight(exerciseId: String) -> Double? {
        sets.first { $0.exerciseId == exerciseId && $0.weightKg != nil }?.weightKg
    }

    // MARK: file

    private static func read(_ fileURL: URL?) -> [LoggedSet]? {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL), let loaded = try? JSONDecoder().decode([LoggedSet].self, from: data) else {
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
