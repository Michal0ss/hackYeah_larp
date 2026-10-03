import Contracts
import Foundation

/// What the user said after workouts (effort, pain, a note), kept on the phone as a JSON file
/// (`session-feedback.json`). It reaches the model only through the consent-gated coach tool `get_session_feedback`.
/// A missing or broken file means "no feedback yet", never a crash.
public final class SessionFeedbackStore: SessionFeedbackStoring, @unchecked Sendable {
    /// Older entries are dropped.
    public static let maxEntries = 200

    private let lock = NSLock()
    private var stored: [SessionFeedback] = []
    private let fileURL: URL?

    /// - Parameter fileURL: nil keeps the feedback in memory (tests, previews).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let loaded = try? Self.decoder.decode([SessionFeedback].self, from: data) {
            stored = loaded
        }
    }

    /// `Application Support/Forma/session-feedback.json`.
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Forma", isDirectory: true).appendingPathComponent("session-feedback.json")
    }

    /// One entry per session: feedback given again for the same session replaces the earlier one.
    public func save(_ feedback: SessionFeedback) async { insert(feedback) }

    private func insert(_ feedback: SessionFeedback) {
        lock.lock(); defer { lock.unlock() }
        stored.removeAll { $0.id == feedback.id || $0.sessionId == feedback.sessionId }
        stored.insert(feedback, at: 0)
        stored.sort { $0.date > $1.date }
        if stored.count > Self.maxEntries { stored.removeLast(stored.count - Self.maxEntries) }
        persist()
    }

    /// Newest first.
    public func feedbacks(limit: Int) async -> [SessionFeedback] { newest(limit) }

    private func newest(_ limit: Int) -> [SessionFeedback] {
        lock.lock(); defer { lock.unlock() }
        return Array(stored.prefix(max(0, limit)))
    }

    /// The feedback of one session, if there is any.
    public func feedback(forSession id: UUID) -> SessionFeedback? {
        lock.lock(); defer { lock.unlock() }
        return stored.first { $0.sessionId == id }
    }

    /// Removes the feedback of one session (the user repeats the workout from scratch).
    public func remove(forSession id: UUID) {
        lock.lock(); defer { lock.unlock() }
        stored.removeAll { $0.sessionId == id }
        persist()
    }

    /// Forgets everything (the user deleted all data).
    public func clear() {
        lock.lock()
        stored = []
        lock.unlock()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    private func persist() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(stored).write(to: fileURL, options: .atomic)
        } catch {
            // The feedback stays in memory; losing the file is not worth interrupting the user.
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

/// The phone's own short comment on a workout, from what the user reported. A signal, never a diagnosis.
public enum SessionFeedbackText {
    public static func summary(for feedback: SessionFeedback) -> String {
        var parts: [String] = []
        switch feedback.perceivedExertion {
        case ...3: parts.append("Lekki trening. Jeśli to był plan na regenerację, w porządku. Jeśli nie, następnym razem możesz dołożyć odrobinę.")
        case 4...6: parts.append("Umiarkowany wysiłek, z zapasem. To dobra strefa na większość serii roboczych.")
        case 7...8: parts.append("Ciężki, ale kontrolowany trening. Tak ma wyglądać większość mocnych sesji.")
        default: parts.append("Bardzo duży wysiłek. Kilka takich sesji z rzędu to sygnał, żeby dać lżejszy tydzień.")
        }
        if feedback.plannedSets > 0, feedback.completedSets < feedback.plannedSets {
            parts.append("Zrobione serie: \(feedback.completedSets) z \(feedback.plannedSets).")
        }
        if feedback.hasPain {
            let places = feedback.pain.map { $0.area.title.lowercased() }.joined(separator: ", ")
            parts.append("Zapisano dyskomfort: \(places). To sygnał, nie diagnoza. Jeśli się utrzymuje albo narasta, warto rozważyć konsultację.")
        }
        return parts.joined(separator: " ")
    }
}
