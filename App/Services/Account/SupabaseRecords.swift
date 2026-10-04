import Foundation

/// One record of the person's history as it is stored in the account (`user_records`): its kind, its id, the JSON of
/// the record and when it happened.
struct CloudRecord: Equatable, Sendable {
    var kind: String
    var id: String
    /// A JSON object (what the app's own Codable type encodes to).
    var data: Data
    var occurredAt: Date
}

/// The account tables behind row-level security (`user_records`, `training_plans`, `profiles.onboarding`): the signed-in
/// person can only reach their own rows. Plain REST on the same client as the sign-in.
extension SupabaseAuthClient {
    private static let batch = 100

    // MARK: records

    /// Creates or updates the records (the same id twice is one record). Done in batches.
    func upsertRecords(session: AccountSession, _ records: [CloudRecord]) async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for start in stride(from: 0, to: records.count, by: Self.batch) {
            let rows: [[String: Any]] = try records[start..<min(start + Self.batch, records.count)].map { record in
                [
                    "user_id": session.user.id,
                    "kind": record.kind,
                    "record_id": record.id,
                    "data": try JSONSerialization.jsonObject(with: record.data),
                    "occurred_at": formatter.string(from: record.occurredAt),
                ]
            }
            var request = authorized("rest/v1/user_records?on_conflict=user_id,kind,record_id", method: "POST", session: session)
            request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
            request.httpBody = try JSONSerialization.data(withJSONObject: rows)
            let (data, response) = try await urlSession.data(for: request)
            try Self.check(response, data)
        }
    }

    /// The records of one kind, newest first (up to 1000).
    func fetchRecords(session: AccountSession, kind: String) async throws -> [CloudRecord] {
        let request = authorized("rest/v1/user_records?select=kind,record_id,data,occurred_at&kind=eq.\(kind)&order=occurred_at.desc&limit=1000",
                                 method: "GET", session: session)
        let (data, response) = try await urlSession.data(for: request)
        try Self.check(response, data)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw AuthError.badResponse }
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return rows.compactMap { row in
            guard let kind = row["kind"] as? String, let id = row["record_id"] as? String, let object = row["data"],
                  let json = try? JSONSerialization.data(withJSONObject: object) else { return nil }
            let stamp = row["occurred_at"] as? String ?? ""
            return CloudRecord(kind: kind, id: id, data: json,
                               occurredAt: fractional.date(from: stamp) ?? plain.date(from: stamp) ?? Date())
        }
    }

    /// Deletes records of the person: given ids of one kind, or (nil) all of them.
    func deleteRecords(session: AccountSession, kind: String? = nil, ids: [String]? = nil) async throws {
        var path = "rest/v1/user_records?user_id=eq.\(session.user.id)"
        if let kind { path += "&kind=eq.\(kind)" }
        if let ids {
            guard !ids.isEmpty else { return }
            path += "&record_id=in.(\(ids.joined(separator: ",")))"
        }
        let (data, response) = try await urlSession.data(for: authorized(path, method: "DELETE", session: session))
        try Self.check(response, data)
    }

    // MARK: plan and answers

    func upsertPlan(session: AccountSession, plan: Data) async throws {
        var request = authorized("rest/v1/training_plans?on_conflict=user_id", method: "POST", session: session)
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "user_id": session.user.id, "plan": try JSONSerialization.jsonObject(with: plan), "schema_version": 1,
        ])
        let (data, response) = try await urlSession.data(for: request)
        try Self.check(response, data)
    }

    func fetchPlan(session: AccountSession) async throws -> Data? {
        let (data, response) = try await urlSession.data(for: authorized("rest/v1/training_plans?select=plan&limit=1", method: "GET", session: session))
        try Self.check(response, data)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], let plan = rows.first?["plan"] else { return nil }
        return try JSONSerialization.data(withJSONObject: plan)
    }

    /// The answers from onboarding that are not about health (goal, level, days, minutes, equipment, gear).
    func upsertOnboarding(session: AccountSession, answers: Data) async throws {
        var request = authorized("rest/v1/profiles?on_conflict=user_id", method: "POST", session: session)
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "user_id": session.user.id, "onboarding": try JSONSerialization.jsonObject(with: answers),
        ])
        let (data, response) = try await urlSession.data(for: request)
        try Self.check(response, data)
    }

    func fetchOnboarding(session: AccountSession) async throws -> Data? {
        let (data, response) = try await urlSession.data(for: authorized("rest/v1/profiles?select=onboarding&limit=1", method: "GET", session: session))
        try Self.check(response, data)
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let answers = rows.first?["onboarding"] as? [String: Any], !answers.isEmpty else { return nil }
        return try JSONSerialization.data(withJSONObject: answers)
    }

    /// Empties the plan and the answers of the person (the account itself stays).
    func clearPlanAndOnboarding(session: AccountSession) async throws {
        let (a, ra) = try await urlSession.data(for: authorized("rest/v1/training_plans?user_id=eq.\(session.user.id)", method: "DELETE", session: session))
        try Self.check(ra, a)
        var request = authorized("rest/v1/profiles?user_id=eq.\(session.user.id)", method: "PATCH", session: session)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["onboarding": [String: Any]()])
        let (b, rb) = try await urlSession.data(for: request)
        try Self.check(rb, b)
    }

    // MARK: plumbing

    private func authorized(_ path: String, method: String, session: AccountSession) -> URLRequest {
        var request = URLRequest(url: URL(string: config.url.absoluteString + "/" + path)!, timeoutInterval: 25)
        request.httpMethod = method
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
}
