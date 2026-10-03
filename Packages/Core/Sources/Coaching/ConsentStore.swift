import Contracts
import Foundation

/// The user's consent to pass health summaries (sleep, heart rate, HRV, check-ins, today's recommendation) to the
/// language model through the backend. Kept on the phone as a small JSON file.
///
/// Three states: not decided yet (`date == nil`, the coach asks before the first conversation), granted, declined.
/// Declining is not an error: the coach still works, without health data. Withdrawing is `setGranted(false)`.
/// Readable from anywhere without `await` because the rule is applied right where data would leave the phone.
public final class ConsentStore: @unchecked Sendable {
    /// One shared instance for the app, so two stores never write the same file.
    public static let standard = ConsentStore(fileURL: ConsentStore.defaultFileURL())

    private let lock = NSLock()
    private let fileURL: URL?
    private let now: @Sendable () -> Date
    private var consent: DataConsent

    /// - Parameter fileURL: nil keeps the choice in memory only (tests, previews).
    public init(fileURL: URL?, now: @escaping @Sendable () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.now = now
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? Self.decoder.decode(DataConsent.self, from: data) {
            // A "granted" without a date is not a real choice the user made: treat it as undecided.
            consent = saved.date == nil ? DataConsent() : saved
        } else {
            consent = DataConsent()
        }
    }

    /// `Application Support/Forma/consent.json`.
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Forma", isDirectory: true).appendingPathComponent("consent.json")
    }

    public var current: DataConsent {
        lock.lock(); defer { lock.unlock() }
        return consent
    }

    /// True only after the user explicitly agreed.
    public var isGranted: Bool { current.granted && current.date != nil }

    /// True once the user answered, either way.
    public var isDecided: Bool { current.date != nil }

    /// Records the answer and returns whether it reached the disk (the choice is kept in memory either way).
    @discardableResult
    public func setGranted(_ granted: Bool) -> Bool {
        lock.lock()
        consent = DataConsent(granted: granted, date: now())
        let snapshot = consent
        lock.unlock()
        return write(snapshot)
    }

    /// Back to "not decided yet" (used when the user deletes all data).
    public func reset() {
        lock.lock()
        consent = DataConsent()
        lock.unlock()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    private func write(_ value: DataConsent) -> Bool {
        guard let fileURL else { return true }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(value).write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
