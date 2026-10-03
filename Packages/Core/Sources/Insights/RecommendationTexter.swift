import Foundation
import Contracts

/// Wording of the daily recommendation: the model when it is allowed and available, the phone's own text otherwise.
///
/// - **Consent first.** The recommendation carries health summaries (sleep, HRV, heart rate). It goes to the backend
///   only when the user agreed to share health data with the model (`hasConsent`), or when the data is simulated
///   ("Dane przykładowe", nothing personal). Without that, the phone's own text is used and nothing is sent.
/// - **Never blocks, never fails.** Callers show `localText` right away and swap in `text(for:)` when it arrives.
///   Any problem (offline, timeout, backend template, rejected text) ends in the local text with a warning.
/// - **Double check.** Model text is checked again on the phone with `TextGuard`, the same rules as the backend.
/// - **Cheap.** The same recommendation is fetched once (cached on the phone for a few days), concurrent calls share
///   one request, and a failed request is not repeated for a minute.
public actor RecommendationTexter: RecommendationTexting {
    public struct Options: Sendable {
        public var timeout: TimeInterval
        public var failureCooldown: TimeInterval
        public var maxCachedTexts: Int
        public var cacheDays: Int

        public init(timeout: TimeInterval = 12, failureCooldown: TimeInterval = 60, maxCachedTexts: Int = 14,
                    cacheDays: Int = 3) {
            self.timeout = timeout
            self.failureCooldown = failureCooldown
            self.maxCachedTexts = maxCachedTexts
            self.cacheDays = cacheDays
        }
    }

    private struct Entry: Codable {
        var key: String
        var text: RecommendationText
        var savedAt: Date
    }

    private struct TimedOut: Error {}

    private let fetcher: RecommendationTextFetching
    private let hasConsent: @Sendable () async -> Bool
    private let options: Options
    private let cacheURL: URL?
    private let now: @Sendable () -> Date

    private var entries: [Entry] = []
    private var loaded = false
    private var failures: [String: (date: Date, warnings: [String])] = [:]
    private var inFlight: [String: Task<RecommendationText, Never>] = [:]

    /// - Parameters:
    ///   - hasConsent: whether the user agreed to pass health summaries to the model (Maciek's `DataConsent`).
    ///   - cacheURL: where to keep fetched texts; nil keeps them in memory only.
    public init(fetcher: RecommendationTextFetching, hasConsent: @escaping @Sendable () async -> Bool,
                options: Options = Options(), cacheURL: URL? = RecommendationTexter.defaultCacheURL(),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.fetcher = fetcher
        self.hasConsent = hasConsent
        self.options = options
        self.cacheURL = cacheURL
        self.now = now
    }

    /// `Application Support/Forma/recommendation-texts.json`.
    public static func defaultCacheURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Forma", isDirectory: true).appendingPathComponent("recommendation-texts.json")
    }

    // MARK: RecommendationTexting

    public nonisolated func localText(for recommendation: DailyRecommendation) -> RecommendationText {
        EngineText.make(for: recommendation)
    }

    public func text(for recommendation: DailyRecommendation) async -> RecommendationText {
        let local = EngineText.make(for: recommendation)
        // Simulated data is nothing personal; real data needs the user's consent.
        if !recommendation.isSimulated, !(await hasConsent()) { return local }
        return await resolve(recommendation, local: local)
    }

    /// Forgets fetched texts (e.g. when the user withdraws consent or wipes data).
    public func clearCache() {
        entries = []
        loaded = true
        failures = [:]
        if let cacheURL { try? FileManager.default.removeItem(at: cacheURL) }
    }

    // MARK: Flow

    private func resolve(_ recommendation: DailyRecommendation, local: RecommendationText) async -> RecommendationText {
        let key = Self.key(for: recommendation)
        loadIfNeeded()
        if let hit = entries.first(where: { $0.key == key }) { return hit.text }
        if let failure = failures[key], now().timeIntervalSince(failure.date) < options.failureCooldown {
            return Self.local(local, warnings: failure.warnings)
        }
        if let running = inFlight[key] { return await running.value }

        let task = Task { await self.fetch(recommendation, key: key, local: local) }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    private func fetch(_ recommendation: DailyRecommendation, key: String, local: RecommendationText) async -> RecommendationText {
        do {
            let fetcher = self.fetcher
            let remote = try await Self.withTimeout(options.timeout) { try await fetcher.fetch(recommendation) }
            guard remote.fromModel else {
                return fail(key, local, remote.warnings.isEmpty ? ["template"] : remote.warnings)
            }
            let headline = remote.headline.trimmingCharacters(in: .whitespacesAndNewlines)
            let explanation = remote.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard TextGuard.problems(headline: headline, explanation: explanation, for: recommendation).isEmpty else {
                return fail(key, local, ["ai_text_rejected_on_device"])
            }
            let text = RecommendationText(headline: headline, explanation: explanation, source: .ai)
            store(Entry(key: key, text: text, savedAt: now()))
            return text
        } catch is TimedOut {
            return fail(key, local, ["timeout"])
        } catch {
            return fail(key, local, ["offline"])
        }
    }

    private func fail(_ key: String, _ local: RecommendationText, _ warnings: [String]) -> RecommendationText {
        failures[key] = (now(), warnings)
        return Self.local(local, warnings: warnings)
    }

    private static func local(_ text: RecommendationText, warnings: [String]) -> RecommendationText {
        var copy = text
        copy.warnings = warnings
        return copy
    }

    // MARK: Cache

    /// Same recommendation, same key: decision, wording, factors, care flag, simulation flag and the day.
    static func key(for r: DailyRecommendation) -> String {
        let factors = r.factors.map { "\($0.source.rawValue):\($0.isNegative ? "-" : "+"):\($0.text)" }.joined(separator: "|")
        let day = Int((r.date.timeIntervalSince1970 / 86_400).rounded(.down))
        return [r.decision.rawValue, r.headline, r.suggestedAction, r.careFlag?.reason ?? "", r.isSimulated ? "sim" : "real",
                factors, "\(day)"].joined(separator: "¦")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([Entry].self, from: data)) ?? []
        prune()
    }

    private func store(_ entry: Entry) {
        entries.removeAll { $0.key == entry.key }
        entries.insert(entry, at: 0)
        prune()
        persist()
    }

    private func prune() {
        let oldest = now().addingTimeInterval(-Double(options.cacheDays) * 86_400)
        entries = Array(entries.filter { $0.savedAt >= oldest }.prefix(options.maxCachedTexts))
    }

    private func persist() {
        guard let cacheURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try? data.write(to: cacheURL, options: [.atomic, .completeFileProtection])
        #else
        try? data.write(to: cacheURL, options: .atomic)
        #endif
    }

    // MARK: Timeout

    private static func withTimeout<T: Sendable>(_ seconds: TimeInterval,
                                                 _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
                throw TimedOut()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TimedOut() }
            return first
        }
    }
}
