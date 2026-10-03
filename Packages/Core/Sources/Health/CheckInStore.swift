import Foundation
import Contracts

/// Local storage of check-ins (mood, stress, energy, optional note) as a JSON file on the phone.
/// Implements `CheckInProviding`, so the rule engine and the coach tools read it through the shared protocol.
///
/// - One check-in per calendar day: saving again the same day replaces the earlier one (latest wins).
/// - Values are clamped to 1...5. The note stays on the phone and is never sent anywhere from here.
/// - A missing or unreadable file means an empty history, never a crash.
public actor CheckInStore: CheckInProviding {
    /// How many check-ins are kept. Older ones are dropped on save.
    public static let maxEntries = 400

    /// One shared instance for the app, so two stores never write the same file.
    public static let standard = CheckInStore(fileURL: CheckInStore.defaultFileURL())

    private let fileURL: URL
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var entries: [CheckIn] = []
    private var loaded = false

    public init(fileURL: URL, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.calendar = calendar
        self.now = now
    }

    /// `Application Support/Forma/checkins.json`.
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Forma", isDirectory: true).appendingPathComponent("checkins.json")
    }

    // MARK: CheckInProviding

    /// Check-ins from the last `days` days including today, newest first.
    public func checkIns(days: Int) async -> [CheckIn] {
        loadIfNeeded()
        guard days > 0 else { return [] }
        let today = calendar.startOfDay(for: now())
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
        return entries.filter { $0.date >= start }
    }

    // MARK: Writing

    /// Saves a check-in and returns what was stored (values clamped to 1...5, empty note dropped).
    /// Throws only when the file cannot be written; the in-memory history is still updated.
    @discardableResult
    public func save(_ checkIn: CheckIn) throws -> CheckIn {
        loadIfNeeded()
        var stored = checkIn
        stored.mood = Self.clamp(checkIn.mood)
        stored.stress = Self.clamp(checkIn.stress)
        stored.energy = Self.clamp(checkIn.energy)
        let note = checkIn.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        stored.note = (note?.isEmpty ?? true) ? nil : note

        entries.removeAll { calendar.isDate($0.date, inSameDayAs: stored.date) }
        entries.append(stored)
        entries.sort { $0.date > $1.date }
        if entries.count > Self.maxEntries { entries = Array(entries.prefix(Self.maxEntries)) }
        try persist()
        return stored
    }

    /// Deletes the whole history (the user can wipe their data).
    public func removeAll() throws {
        entries = []
        loaded = true
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: File handling

    private static func clamp(_ value: Int) -> Int { min(5, max(1, value)) }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([CheckIn].self, from: data).sorted { $0.date > $1.date }
        } catch {
            // Unreadable file: keep it aside for inspection and start with an empty history.
            let aside = fileURL.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            entries = []
        }
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
    }
}
