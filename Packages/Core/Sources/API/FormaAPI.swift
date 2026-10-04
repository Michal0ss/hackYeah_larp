import Contracts
import Foundation

/// Client of the Forma backend (backend/, see backend/README.md and backend/openapi.json).
/// Thin on purpose: no caching policy, no fallbacks. Callers (PlanGenerator, CoachChat, content sync) decide
/// what to do on errors, usually "use the local template".
public struct FormaAPI: Sendable {
    public var config: APIConfig
    private let transport: APITransport

    public init(config: APIConfig = .fromBundle(), transport: APITransport = URLSessionTransport()) {
        self.config = config
        self.transport = transport
    }

    // MARK: endpoints

    public func health() async throws -> HealthResponse {
        try await get("health", auth: false)
    }

    /// Returns nil when `etag` is still current (HTTP 304).
    public func catalog(etag: String? = nil) async throws -> (value: CatalogResponse, etag: String?)? {
        try await getCached("v1/catalog", etag: etag)
    }

    public func remoteConfig(etag: String? = nil) async throws -> (value: ConfigResponse, etag: String?)? {
        try await getCached("v1/config", etag: etag)
    }

    /// Never fails because of the model: a template plan comes back with a warning instead.
    public func generatePlan(for profile: UserProfile) async throws -> PlanGenerateResponse {
        struct Body: Encodable { var profile: UserProfile }
        return try await post("v1/plans/generate", body: Body(profile: profile), timeout: 70)
    }

    public func recommendationText(for recommendation: DailyRecommendation) async throws -> RecommendationTextResponse {
        struct Body: Encodable { var recommendation: DailyRecommendation }
        return try await post("v1/texts/recommendation", body: Body(recommendation: recommendation), timeout: 25)
    }

    /// Deletes the signed-in person's cloud account and what is stored for it (profile and plan). `accountToken` is
    /// the person's own access token; the server identifies them by it. Data on the phone is not touched. Throws
    /// `APIError`: code `invalid_account_token` (sign in again), `account_unavailable` (try later or not configured).
    public func deleteAccount(accountToken: String) async throws {
        var request = try makeRequest("v1/account", method: "DELETE", timeout: 20)
        request.setValue(accountToken, forHTTPHeaderField: "X-Account-Token")
        let (data, head) = try await perform(request)
        guard head.statusCode == 204 || head.statusCode == 200 else {
            throw Self.serverError(status: head.statusCode, body: data, head: head)
        }
    }

    /// One JSON answer (no streaming).
    public func chat(_ request: ChatRequest) async throws -> ChatResponse {
        var request = request
        request.stream = false
        return try await post("v1/coach/chat", body: request, timeout: 90)
    }

    /// Streamed answer. Throws `APIError` before the first event for problems like a bad conversation or a missing
    /// consent; failures after the stream started arrive as `.error` events. Finish the loop on `.done`.
    public func chatStream(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        var request = request
        request.stream = true
        let built: URLRequest
        do {
            built = try makeRequest("v1/coach/chat", method: "POST", body: Self.encoder.encode(request), timeout: 120)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (head, lines) = try await transport.stream(built)
                    guard head.statusCode == 200 else {
                        var body = ""
                        for try await line in lines { body += line }
                        throw Self.serverError(status: head.statusCode, body: Data(body.utf8), head: head)
                    }
                    var parser = ChatEventParser(decoder: Self.decoder)
                    for try await line in lines {
                        if let event = try parser.feed(line) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch let error as APIError {
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish()
                } catch let error as DecodingError {
                    continuation.finish(throwing: APIError.invalidResponse("\(error)"))
                } catch {
                    continuation.finish(throwing: APIError.transport(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: plumbing

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601  // "2026-10-03T07:00:00Z", what the server expects
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func makeRequest(_ path: String, method: String, body: Data? = nil, timeout: TimeInterval = 20,
                             auth: Bool = true, etag: String? = nil) throws -> URLRequest {
        guard let base = config.baseURL else { throw APIError.notConfigured }
        var request = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: timeout)
        request.httpMethod = method
        // ETags are handled by us (see catalog/remoteConfig); the system cache would turn a 304 into a 200.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(config.deviceId, forHTTPHeaderField: "X-Device-Id")
        if auth, !config.token.isEmpty { request.setValue("Bearer \(config.token)", forHTTPHeaderField: "Authorization") }
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try Self.decoder.decode(T.self, from: data) }
        catch { throw APIError.invalidResponse("\(error)") }
    }

    private func get<T: Decodable>(_ path: String, auth: Bool = true) async throws -> T {
        let (data, head) = try await perform(try makeRequest(path, method: "GET", auth: auth))
        guard head.statusCode == 200 else { throw Self.serverError(status: head.statusCode, body: data, head: head) }
        return try decode(T.self, data)
    }

    private func getCached<T: Decodable>(_ path: String, etag: String?) async throws -> (value: T, etag: String?)? {
        let (data, head) = try await perform(try makeRequest(path, method: "GET", etag: etag))
        if head.statusCode == 304 { return nil }
        guard head.statusCode == 200 else { throw Self.serverError(status: head.statusCode, body: data, head: head) }
        return (try decode(T.self, data), head.value(forHTTPHeaderField: "ETag"))
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B, timeout: TimeInterval) async throws -> T {
        let payload: Data
        do { payload = try Self.encoder.encode(body) } catch { throw APIError.invalidResponse("encode: \(error)") }
        let (data, head) = try await perform(try makeRequest(path, method: "POST", body: payload, timeout: timeout))
        guard head.statusCode == 200 else { throw Self.serverError(status: head.statusCode, body: data, head: head) }
        return try decode(T.self, data)
    }

    static func serverError(status: Int, body: Data, head: HTTPURLResponse) -> APIError {
        let retry = head.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
        if let envelope = try? decoder.decode(ErrorEnvelope.self, from: body) {
            return .server(envelope.error, status: status, retryAfter: retry)
        }
        return .server(ServerError(code: "http_\(status)", message: "Błąd serwera (\(status))."), status: status, retryAfter: retry)
    }
}
