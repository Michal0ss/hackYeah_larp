import Contracts
import Foundation
import Health
import Observation
import Plan

/// What the account has that a new phone can start from: the plan and the answers from onboarding.
struct AccountSetup {
    var profile: UserProfile
    var plan: TrainingPlan
}

/// Something deleted on this phone that the account must forget too.
enum CloudDeletion {
    /// Sets and the finished-session mark of one session ("Powtórz trening").
    case session(sets: [UUID], completionId: UUID?)
    /// "Usuń wszystkie dane".
    case everything
}

/// Keeps the person's history in their account while they are signed in, so it follows them to another phone.
///
/// What goes: the plan, the answers from onboarding that are not about health, the sets they did (with the weight where
/// they typed one), the finished sessions, the analyses and live sets (scores, findings, numbers) and the step goal.
/// What never goes (and the database refuses): video and poses, the chat, Apple Health data, check-ins, the feedback
/// after a workout (effort, pain) and the health history. Everything else stays on the phone.
///
/// Pushing is an upsert of what this phone has (the same id is one record), so it can be repeated at any time. Pulling
/// adds what the account has and the phone does not. A deletion on the phone is sent to the account at once.
@MainActor
@Observable
final class CloudSync {
    enum State: Equatable {
        case idle
        case syncing
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastSyncedAt: Date?
    private(set) var restoredCount = 0

    @ObservationIgnored private unowned let store: AppStore
    @ObservationIgnored private let account: AccountStore
    @ObservationIgnored private var lastAttempt: Date?
    private static let lastSyncKey = "forma.cloud.lastSync"

    init(store: AppStore, account: AccountStore) {
        self.store = store
        self.account = account
        lastSyncedAt = UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date
    }

    private var services: AppServices { store.services }

    // MARK: Push

    /// Sends the plan, the answers and every record this phone has. `force` skips the 20 second pause between runs.
    func push(force: Bool = false) async {
        guard account.isSignedIn, state != .syncing else { return }
        if !force, let last = lastAttempt, Date().timeIntervalSince(last) < 20 { return }
        lastAttempt = Date()
        guard let session = await account.freshSession() else { return }
        state = .syncing
        do {
            if store.onboardingCompleted {
                if let plan = Self.planJSON(services.planStore.templatePlan) { try await account.client.upsertPlan(session: session, plan: plan) }
                if let answers = Self.answersJSON(store.profile) { try await account.client.upsertOnboarding(session: session, answers: answers) }
            }
            try await account.client.upsertRecords(session: session, records())
            finish()
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    // MARK: Pull

    /// The plan and the answers of the account, nil when it has none yet (a new account).
    func fetchSetup() async -> AccountSetup? {
        guard account.isSignedIn, let session = await account.freshSession() else { return nil }
        state = .syncing
        defer { if state == .syncing { state = .idle } }
        guard let planData = try? await account.client.fetchPlan(session: session),
              let answers = try? await account.client.fetchOnboarding(session: session),
              let plan = try? Self.decoder.decode(TrainingPlan.self, from: planData),
              let profile = Self.profile(from: answers) else { return nil }
        return AccountSetup(profile: profile, plan: plan)
    }

    /// Adds to this phone what the account has and the phone does not.
    func pull() async {
        guard account.isSignedIn, let session = await account.freshSession() else { return }
        state = .syncing
        do {
            let client = account.client
            let sets: [LoggedSet] = try await client.fetchRecords(session: session, kind: Kind.loggedSet).compactMap(Self.decode)
            let completions: [SessionCompletion] = try await client.fetchRecords(session: session, kind: Kind.completion).compactMap(Self.decode)
            let results: [TechniqueResult] = try await client.fetchRecords(session: session, kind: Kind.techniqueResult).compactMap(Self.decode)
            let summaries: [SetSummary] = try await client.fetchRecords(session: session, kind: Kind.setSummary).compactMap(Self.decode)
            let goals: [StepGoal] = try await client.fetchRecords(session: session, kind: Kind.stepGoal).compactMap(Self.decode)

            let known = Set(services.trainingLog.sets.map(\.id))
            let newSets = sets.filter { !known.contains($0.id) }
            newSets.forEach { services.trainingLog.record($0) }
            var added = newSets.count
            added += services.planStore.restore(completions: completions)
            added += services.localHistory.restore(results: results, sets: summaries)
            if let goal = goals.first, (services.stepGoalStore.current?.date ?? .distantPast) < goal.date {
                services.stepGoalStore.set(goal)
                store.reloadStepGoal()
                added += 1
            }
            restoredCount = added
            finish()
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    /// Both ways: what this phone has goes up, what the account has comes down.
    func syncNow() async {
        await push(force: true)
        if state != .syncing, case .failed = state { return }
        await pull()
    }

    // MARK: Deleting

    func forget(_ deletion: CloudDeletion) async {
        guard account.isSignedIn, let session = await account.freshSession() else { return }
        do {
            switch deletion {
            case .session(let sets, let completionId):
                try await account.client.deleteRecords(session: session, kind: Kind.loggedSet, ids: sets.map(\.uuidString))
                try await account.client.deleteRecords(session: session, kind: Kind.completion, ids: completionId.map { [$0.uuidString] })
            case .everything:
                try await account.client.deleteRecords(session: session)
                try await account.client.clearPlanAndOnboarding(session: session)
            }
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    // MARK: Records

    private enum Kind {
        static let loggedSet = "logged_set"
        static let completion = "completion"
        static let techniqueResult = "technique_result"
        static let setSummary = "set_summary"
        static let stepGoal = "step_goal"
    }

    /// Every record on this phone that belongs in the account (nothing simulated).
    private func records() -> [CloudRecord] {
        var all: [CloudRecord] = []
        func add<T: Encodable>(_ kind: String, id: String, _ value: T, at date: Date) {
            if let data = try? Self.encoder.encode(value) { all.append(CloudRecord(kind: kind, id: id, data: data, occurredAt: date)) }
        }
        for set in services.trainingLog.sets { add(Kind.loggedSet, id: set.id.uuidString, set, at: set.date) }
        for done in services.planStore.completions { add(Kind.completion, id: done.id.uuidString, done, at: done.date) }
        for result in services.localHistory.recordedResults() { add(Kind.techniqueResult, id: result.id.uuidString, result, at: result.date) }
        for summary in services.localHistory.recordedSets() { add(Kind.setSummary, id: summary.id.uuidString, summary, at: summary.date) }
        if let goal = services.stepGoalStore.current { add(Kind.stepGoal, id: "current", goal, at: goal.date) }
        return all
    }

    // MARK: Encoding

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

    private static func decode<T: Decodable>(_ record: CloudRecord) -> T? {
        try? decoder.decode(T.self, from: record.data)
    }

    /// The plan without `notices` (how it came to be can reveal what the person typed; the database refuses it).
    private static func planJSON(_ plan: TrainingPlan?) -> Data? {
        guard let plan, let data = try? encoder.encode(plan),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        object.removeValue(forKey: "notices")
        return try? JSONSerialization.data(withJSONObject: object)
    }

    /// The answers that are not about health: goal, level, days, minutes, equipment and gear. Free text, the movements
    /// left out and the easy start say something about health and stay on the phone.
    private static func answersJSON(_ profile: UserProfile) -> Data? {
        guard let data = try? encoder.encode(profile),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let allowed = ["goal", "level", "daysPerWeek", "sessionMinutes", "equipment", "gear"]
        return try? JSONSerialization.data(withJSONObject: object.filter { allowed.contains($0.key) })
    }

    private static func profile(from answers: Data) -> UserProfile? {
        guard var object = try? JSONSerialization.jsonObject(with: answers) as? [String: Any] else { return nil }
        object["avoid"] = ""
        object["avoidTags"] = [String]()
        object["easyStart"] = false
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? decoder.decode(UserProfile.self, from: data)
    }

    private func finish() {
        lastSyncedAt = Date()
        UserDefaults.standard.set(lastSyncedAt, forKey: Self.lastSyncKey)
        state = .idle
    }

    private static func message(for error: Error) -> String {
        if error is URLError { return "Brak połączenia. Spróbuję ponownie przy następnej okazji." }
        return "Nie udało się zsynchronizować z kontem. Spróbuję ponownie."
    }
}
