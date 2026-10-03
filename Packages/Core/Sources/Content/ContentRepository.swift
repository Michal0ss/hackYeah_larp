import API
import Contracts
import Foundation

/// The exercise catalog and remote config (scoring, insights, tempo), from three places, newest wins:
///   1. the copy bundled in the app (Resources/, made by scripts/sync_content.py from content/),
///   2. the last copy fetched from the backend, kept on disk (works offline),
///   3. a fresh fetch from the backend (`refresh`), revalidated with ETags.
/// Reading is synchronous and never fails: there is always at least the bundled copy.
public final class ContentRepository: ExerciseCatalogProviding, @unchecked Sendable {
    public enum Source: String, Sendable { case bundled, cached, remote }

    public struct Snapshot: Sendable {
        public var source: Source
        public var catalogVersion: String
        public var exercises: [ExerciseItem]
        public var configVersion: String
        public var scoring: JSONValue
        public var insights: JSONValue
        public var tempo: JSONValue
    }

    /// Shared instance used by the app (bundled copy plus the disk cache).
    public static let shared = ContentRepository()

    private let lock = NSLock()
    private var current: Snapshot
    private var catalogETag: String?
    private var configETag: String?
    private let cacheDirectory: URL?
    /// Bump when the Codable types of the cached content change: older caches are then ignored and refetched.
    private static let cacheFormat = "3"

    /// `cacheDirectory` nil = no disk cache (handy for previews).
    public init(cacheDirectory: URL? = ContentRepository.defaultCacheDirectory()) {
        self.cacheDirectory = cacheDirectory
        current = Self.bundledSnapshot()
        loadCache()
    }

    // MARK: reading

    public var snapshot: Snapshot {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    public var exercises: [ExerciseItem] { snapshot.exercises }

    /// Numbers of one config object, e.g. `numbers("tempo", "phaseTracker")` for PhaseTrackerConfig.
    public func numbers(_ section: String, _ key: String) -> [String: Double] {
        let s = snapshot
        let root: JSONValue
        switch section {
        case "scoring": root = s.scoring
        case "insights": root = s.insights
        default: root = s.tempo
        }
        guard case .object(let values)? = root[key] else { return [:] }
        return values.compactMapValues(\.doubleValue)
    }

    /// Raw JSON of one config section, e.g. to decode `InsightThresholds`.
    public func configData(_ section: String) -> Data? {
        let s = snapshot
        let value: JSONValue
        switch section {
        case "scoring": value = s.scoring
        case "insights": value = s.insights
        default: value = s.tempo
        }
        return try? JSONEncoder().encode(value)
    }

    /// The bundled plan template rules (content/plan_templates.json), for building a plan offline.
    public static func bundledPlanTemplates() -> Data? { bundledData("plan_templates") }

    // MARK: refreshing

    /// Fetches newer content from the backend. Safe to call on every launch: a 304 costs almost nothing and any
    /// failure keeps what we have. Returns true when something changed.
    @discardableResult
    public func refresh(using api: FormaAPI) async -> Bool {
        var changed = false
        if let fetched = try? await api.catalog(etag: etagOfCatalog()),
           Self.isUsable(fetched.value.exercises) {
            update { $0.source = .remote; $0.catalogVersion = fetched.value.version; $0.exercises = fetched.value.exercises }
            setETag(fetched.etag, catalog: true)
            save(fetched.value, as: "catalog.json")
            changed = true
        }
        if let fetched = try? await api.remoteConfig(etag: etagOfConfig()) {
            update {
                $0.source = .remote
                $0.configVersion = fetched.value.version
                $0.scoring = fetched.value.scoring; $0.insights = fetched.value.insights; $0.tempo = fetched.value.tempo
            }
            setETag(fetched.etag, catalog: false)
            save(fetched.value, as: "config.json")
            changed = true
        }
        return changed
    }

    // MARK: internals

    private static func isUsable(_ exercises: [ExerciseItem]) -> Bool {
        !exercises.isEmpty && Set(exercises.map(\.id)).count == exercises.count
    }

    private func update(_ change: (inout Snapshot) -> Void) {
        lock.lock(); defer { lock.unlock() }
        change(&current)
    }

    private func etagOfCatalog() -> String? { lock.lock(); defer { lock.unlock() }; return catalogETag }
    private func etagOfConfig() -> String? { lock.lock(); defer { lock.unlock() }; return configETag }

    private func setETag(_ etag: String?, catalog: Bool) {
        lock.lock()
        if catalog { catalogETag = etag } else { configETag = etag }
        let values = ["catalog": catalogETag, "config": configETag, "format": Self.cacheFormat].compactMapValues { $0 }
        lock.unlock()
        if let data = try? JSONEncoder().encode(values) { write(data, "etags.json") }
    }

    private func save<T: Encodable>(_ value: T, as name: String) {
        if let data = try? JSONEncoder().encode(value) { write(data, name) }
    }

    private func write(_ data: Data, _ name: String) {
        guard let dir = cacheDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
    }

    private func read(_ name: String) -> Data? {
        cacheDirectory.flatMap { try? Data(contentsOf: $0.appendingPathComponent(name)) }
    }

    private func loadCache() {
        let decoder = JSONDecoder()
        guard let data = read("etags.json"), let tags = try? decoder.decode([String: String].self, from: data),
              tags["format"] == Self.cacheFormat else { return }  // no cache, or written by an older app version
        catalogETag = tags["catalog"]; configETag = tags["config"]
        if let data = read("catalog.json"), let catalog = try? decoder.decode(CatalogResponse.self, from: data),
           Self.isUsable(catalog.exercises) {
            current.source = .cached; current.catalogVersion = catalog.version; current.exercises = catalog.exercises
        } else { catalogETag = nil }
        if let data = read("config.json"), let config = try? decoder.decode(ConfigResponse.self, from: data) {
            current.source = .cached; current.configVersion = config.version
            current.scoring = config.scoring; current.insights = config.insights; current.tempo = config.tempo
        } else { configETag = nil }
    }

    public static func defaultCacheDirectory() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Forma/content", isDirectory: true)
    }

    // MARK: bundled copy

    private static func bundledData(_ name: String) -> Data? {
        Bundle.module.url(forResource: name, withExtension: "json").flatMap { try? Data(contentsOf: $0) }
    }

    private static func bundledSnapshot() -> Snapshot {
        struct BundledCatalog: Decodable { var exercises: [ExerciseItem] }
        let decoder = JSONDecoder()
        let exercises = bundledData("catalog").flatMap { try? decoder.decode(BundledCatalog.self, from: $0) }?.exercises
        func section(_ name: String) -> JSONValue {
            bundledData(name).flatMap { try? decoder.decode(JSONValue.self, from: $0) } ?? .object([:])
        }
        return Snapshot(source: .bundled, catalogVersion: "bundled", exercises: exercises ?? SampleData.catalog,
                        configVersion: "bundled", scoring: section("scoring"), insights: section("insights"),
                        tempo: section("tempo"))
    }
}
