import Foundation

/// The error body every non-2xx response has: {"error": {"code", "message", "requestId"}}.
public struct ServerError: Codable, Equatable, Sendable {
    public var code: String
    public var message: String
    public var requestId: String?
}

struct ErrorEnvelope: Decodable {
    var error: ServerError
}

public enum APIError: Error, Equatable, Sendable {
    /// The server answered with an error. Switch on `error.code` (unauthorized, rate_limited, ai_unavailable,
    /// consent_required, invalid_request, chat_too_long, ...). `retryAfter` is set for 429 and 503.
    case server(ServerError, status: Int, retryAfter: TimeInterval?)
    /// No answer: offline, timeout, wrong address.
    case transport(String)
    /// The answer was not what the contract says.
    case invalidResponse(String)
    /// The backend address is not configured.
    case notConfigured

    public var code: String? {
        if case .server(let e, _, _) = self { return e.code }
        return nil
    }

    /// True when trying again later can work (network, rate limit, model unavailable).
    public var isRetryable: Bool {
        switch self {
        case .transport: return true
        case .server(let e, let status, _): return status == 429 || status == 503 || e.code == "ai_unavailable"
        default: return false
        }
    }

    /// Polish text for the user.
    public var userMessage: String {
        switch self {
        case .server(let e, _, _): return e.message
        case .transport: return "Brak połączenia z serwerem. Sprawdź internet i spróbuj ponownie."
        case .invalidResponse: return "Serwer odpowiedział w nieoczekiwany sposób."
        case .notConfigured: return "Adres serwera nie jest ustawiony."
        }
    }
}
