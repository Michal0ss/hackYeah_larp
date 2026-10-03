import Contracts
import Foundation

/// The conversation with the coach, kept on the phone as a JSON file. Only plain messages are stored (text and the
/// names of the data the coach used), never tool results: those are fetched again when needed, and old health
/// data must not outlive the user's consent.
///
/// A missing or unreadable file means an empty conversation, never a crash.
public actor CoachHistoryStore {
    /// Older messages are dropped on save.
    public static let maxMessages = 200

    /// One shared instance for the app, so two stores never write the same file.
    public static let standard = CoachHistoryStore(fileURL: CoachHistoryStore.defaultFileURL())

    private let fileURL: URL?
    private var messages: [ChatMessage] = []
    private var loaded = false

    /// - Parameter fileURL: nil keeps the conversation in memory only (tests, previews).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    /// `Application Support/Forma/coach-chat.json`.
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Forma", isDirectory: true).appendingPathComponent("coach-chat.json")
    }

    /// Oldest first.
    public func all() -> [ChatMessage] {
        loadIfNeeded()
        return messages
    }

    public func append(_ newMessages: [ChatMessage]) {
        loadIfNeeded()
        messages.append(contentsOf: newMessages)
        if messages.count > Self.maxMessages { messages.removeFirst(messages.count - Self.maxMessages) }
        save()
    }

    /// Stores the new state of a proposal (accepted, dismissed, undone) in the message it belongs to.
    public func update(_ proposal: PlanChangeProposal) {
        loadIfNeeded()
        for message in messages.indices {
            if let index = messages[message].proposals.firstIndex(where: { $0.id == proposal.id }) {
                messages[message].proposals[index] = proposal
                save()
                return
            }
        }
    }

    public func clear() {
        messages = []
        loaded = true
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let saved = try? Self.decoder.decode([ChatMessage].self, from: data) else { return }
        messages = saved
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(messages).write(to: fileURL, options: .atomic)
        } catch {
            // The conversation stays in memory; losing the file is not worth interrupting the user.
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
