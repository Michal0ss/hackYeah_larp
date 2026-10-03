import Foundation

/// Talks to Supabase Auth (sign-in with Google through PKCE) and to the two account tables. Plain URLSession, no extra
/// dependency. The language model and the Forma backend are not involved: this is the account service only.
struct SupabaseAuthClient: Sendable {
    enum AuthError: Error, Equatable {
        /// The reply was not what the service sends.
        case badResponse
        /// The service refused (wrong code, provider switched off, expired refresh token...). `message` is for logs.
        case server(status: Int, message: String?)
        /// The sign-in page came back without a code (the person cancelled, or the provider reported an error).
        case noCode(message: String?)
    }

    let config: AccountConfig
    var urlSession: URLSession = .shared

    // MARK: Sign in

    /// The page that starts "Continue with Google". `challenge` is `PKCE.challenge(for:)` of a verifier kept in the app.
    func authorizeURL(challenge: String) -> URL {
        var parts = URLComponents(url: config.url.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: config.callbackURL.absoluteString),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
            // The sign-in browser remembers the last Google account; always let the person pick which one to use.
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        return parts.url!
    }

    /// The code from `forma://auth-callback?code=...`, or the reason it is missing.
    static func code(from callback: URL) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty { return code }
        let reason = items.first(where: { $0.name == "error_description" })?.value
            ?? items.first(where: { $0.name == "error" })?.value
        throw AuthError.noCode(message: reason)
    }

    func exchange(code: String, verifier: String) async throws -> AccountSession {
        let body = try JSONSerialization.data(withJSONObject: ["auth_code": code, "code_verifier": verifier])
        return try await token(grant: "pkce", body: body)
    }

    func refresh(_ session: AccountSession) async throws -> AccountSession {
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": session.refreshToken])
        return try await token(grant: "refresh_token", body: body)
    }

    func signOut(accessToken: String) async {
        var request = makeRequest("auth/v1/logout", method: "POST")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try? await urlSession.data(for: request)
    }

    // MARK: Account tables

    /// Creates or updates the person's row in `profiles` (name and what they agreed to). Rows are protected by
    /// row-level security: the service only lets the signed-in person write their own.
    func upsertProfile(session: AccountSession, consentAt: Date, policyVersion: String) async throws {
        var request = makeRequest("rest/v1/profiles?on_conflict=user_id", method: "POST")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        let formatter = ISO8601DateFormatter()
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "user_id": session.user.id,
            "first_name": session.user.firstName,
            "last_name": session.user.lastName,
            "terms_accepted_at": formatter.string(from: consentAt),
            "policy_version": policyVersion,
        ])
        let (data, response) = try await urlSession.data(for: request)
        try Self.check(response, data)
    }

    // MARK: Internals

    private func token(grant: String, body: Data) async throws -> AccountSession {
        var request = makeRequest("auth/v1/token?grant_type=\(grant)", method: "POST")
        request.httpBody = body
        let (data, response) = try await urlSession.data(for: request)
        try Self.check(response, data)
        return try Self.session(from: data, now: Date())
    }

    private func makeRequest(_ path: String, method: String) -> URLRequest {
        // `appendingPathComponent` would escape the "?", so the path with its query is joined as a string.
        let url = URL(string: config.url.absoluteString + "/" + path)!
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw AuthError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = (object?["msg"] ?? object?["error_description"] ?? object?["message"]) as? String
            throw AuthError.server(status: http.statusCode, message: message)
        }
    }

    /// Reads the token reply into a session. `now` is injected so the expiry is testable.
    static func session(from data: Data, now: Date) throws -> AccountSession {
        struct Reply: Decodable {
            struct Meta: Decodable {
                var givenName: String?, familyName: String?, fullName: String?, name: String?
            }
            struct Person: Decodable {
                var id: String
                var email: String?
                var userMetadata: Meta?
            }
            var accessToken: String
            var refreshToken: String
            var expiresIn: Double
            var user: Person
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let reply = try? decoder.decode(Reply.self, from: data) else { throw AuthError.badResponse }
        let meta = reply.user.userMetadata
        let name = PersonName.split(given: meta?.givenName, family: meta?.familyName, full: meta?.fullName ?? meta?.name)
        return AccountSession(
            accessToken: reply.accessToken, refreshToken: reply.refreshToken,
            expiresAt: now.addingTimeInterval(reply.expiresIn),
            user: AccountUser(id: reply.user.id, email: reply.user.email, firstName: name.first, lastName: name.last))
    }
}
