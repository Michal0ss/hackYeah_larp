import Contracts
import Foundation

/// Technique and live-set results recorded on this phone (JSON file). Michał owns `TechniqueHistoryProviding`;
/// Bartek's analyses and the live set both write here. Falls back to the sample result while nothing was recorded,
/// so the engine and the screens have something to show (marked as simulated).
final class LocalTechniqueHistory: TechniqueHistoryProviding, @unchecked Sendable {
    static let shared = LocalTechniqueHistory()

    private struct Stored: Codable {
        var results: [TechniqueResult] = []
        var sets: [SetSummary] = []
    }

    private let lock = NSLock()
    private var stored = Stored()
    private let url: URL?

    init(url: URL? = LocalTechniqueHistory.defaultURL()) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url), let loaded = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = loaded
        }
    }

    func results(limit: Int) async -> [TechniqueResult] {
        lock.lock(); defer { lock.unlock() }
        return stored.results.isEmpty ? [SampleData.technique] : Array(stored.results.prefix(limit))
    }

    func setSummaries(limit: Int) async -> [SetSummary] {
        lock.lock(); defer { lock.unlock() }
        return Array(stored.sets.prefix(limit))
    }

    /// Stores a finished set. Returns the technique result derived from it (nil when technique was not assessed).
    @discardableResult
    func record(_ set: SetSummary) -> TechniqueResult? {
        lock.lock(); defer { lock.unlock() }
        guard !stored.sets.contains(where: { $0.id == set.id }) else { return nil }
        stored.sets.insert(set, at: 0)
        var derived: TechniqueResult?
        if let score = set.techniqueScore {
            let result = TechniqueResult(exerciseId: set.exerciseId, date: set.date, score: score,
                                         componentScores: ["tempo": set.tempoScore], findings: set.techniqueFindings,
                                         reps: [], isSimulated: set.isSimulated)
            stored.results.insert(result, at: 0)
            derived = result
        }
        stored.sets = Array(stored.sets.prefix(200))
        stored.results = Array(stored.results.prefix(200))
        persist()
        return derived
    }

    /// Bartek's video analyses call this.
    func record(_ result: TechniqueResult) {
        lock.lock(); defer { lock.unlock() }
        stored.results.insert(result, at: 0)
        stored.results = Array(stored.results.prefix(200))
        persist()
    }

    private func persist() {
        guard let url, let data = try? JSONEncoder().encode(stored) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func defaultURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Forma/history.json")
    }
}

/// Check-ins kept in memory until Wiktor's persistent store (`feat/wiktor-checkin-store`) replaces it.
final class InMemoryCheckIns: CheckInProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [CheckIn] = [SampleData.checkIn]

    func add(_ checkIn: CheckIn) {
        lock.lock(); defer { lock.unlock() }
        items.insert(checkIn, at: 0)
    }

    func checkIns(days: Int) async -> [CheckIn] {
        lock.lock(); defer { lock.unlock() }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return items.filter { $0.date >= start }.sorted { $0.date > $1.date }
    }
}
