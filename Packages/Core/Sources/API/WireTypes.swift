import Contracts
import Foundation

// Request and response bodies that are not in Contracts. Field names match backend/openapi.json.

public struct CatalogResponse: Codable, Equatable, Sendable {
    public var version: String
    public var exercises: [ExerciseItem]
}

/// Remote configuration: thresholds for scoring, insights and tempo (content/config/*.json).
public struct ConfigResponse: Codable, Equatable, Sendable {
    public var version: String
    public var scoring: JSONValue
    public var insights: JSONValue
    public var tempo: JSONValue
}

public struct HealthResponse: Codable, Equatable, Sendable {
    public var status: String
    public var version: String
    public var env: String
    /// "mock" (offline stand-in) or "gemini".
    public var aiMode: String
    public var contentVersion: String
}

public struct PlanGenerateResponse: Codable, Equatable, Sendable {
    public var plan: TrainingPlan
    /// ai_unavailable, ai_invalid_plan, ai_mock, avoid_text_not_applied. The plan is still usable.
    public var warnings: [String]
}

public struct RecommendationTextResponse: Codable, Equatable, Sendable {
    public var headline: String
    public var explanation: String
    /// "ai" or "template"
    public var source: String
    public var warnings: [String]
}

// MARK: coach chat

public enum ChatBlock: Codable, Equatable, Sendable {
    case text(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseId: String, content: String, isError: Bool)

    private enum Keys: String, CodingKey { case type, text, id, name, input, toolUseId, content, isError }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "text": self = .text(try c.decode(String.self, forKey: .text))
        case "tool_use":
            self = .toolUse(id: try c.decode(String.self, forKey: .id), name: try c.decode(String.self, forKey: .name),
                            input: try c.decodeIfPresent(JSONValue.self, forKey: .input) ?? .object([:]))
        case "tool_result":
            self = .toolResult(toolUseId: try c.decode(String.self, forKey: .toolUseId),
                               content: try c.decode(String.self, forKey: .content),
                               isError: try c.decodeIfPresent(Bool.self, forKey: .isError) ?? false)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown block type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .text(let text):
            try c.encode("text", forKey: .type); try c.encode(text, forKey: .text)
        case .toolUse(let id, let name, let input):
            try c.encode("tool_use", forKey: .type); try c.encode(id, forKey: .id)
            try c.encode(name, forKey: .name); try c.encode(input, forKey: .input)
        case .toolResult(let toolUseId, let content, let isError):
            try c.encode("tool_result", forKey: .type); try c.encode(toolUseId, forKey: .toolUseId)
            try c.encode(content, forKey: .content); try c.encode(isError, forKey: .isError)
        }
    }
}

public enum WireRole: String, Codable, Sendable { case user, assistant }

/// One message of the conversation the app sends (the server is stateless: send the whole history).
public struct WireMessage: Codable, Equatable, Sendable {
    public var role: WireRole
    public var blocks: [ChatBlock]

    public init(role: WireRole, blocks: [ChatBlock]) {
        self.role = role
        self.blocks = blocks
    }

    public static func user(_ text: String) -> WireMessage { WireMessage(role: .user, blocks: [.text(text)]) }
    public static func assistant(_ text: String) -> WireMessage { WireMessage(role: .assistant, blocks: [.text(text)]) }

    private enum Keys: String, CodingKey { case role, content }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        role = try c.decode(WireRole.self, forKey: .role)
        if let text = try? c.decode(String.self, forKey: .content) { blocks = [.text(text)] }
        else { blocks = try c.decode([ChatBlock].self, forKey: .content) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(role, forKey: .role)
        try c.encode(blocks, forKey: .content)
    }
}

public struct ChatContext: Codable, Equatable, Sendable {
    public var profile: UserProfile
    /// Sent only with health consent (the server ignores it otherwise).
    public var todayRecommendation: DailyRecommendation?
    /// Where in the workout the question was asked (screen, set, last set as numbers). Training data only, so it is
    /// sent regardless of the health consent.
    public var workout: WorkoutContext?

    public init(profile: UserProfile, todayRecommendation: DailyRecommendation? = nil, workout: WorkoutContext? = nil) {
        self.profile = profile
        self.todayRecommendation = todayRecommendation
        self.workout = workout
    }
}

public struct ChatRequest: Codable, Equatable, Sendable {
    public var messages: [WireMessage]
    public var context: ChatContext?
    public var consent: Consent
    public var stream: Bool

    public struct Consent: Codable, Equatable, Sendable {
        public var health: Bool
        public init(health: Bool) { self.health = health }
    }

    public init(messages: [WireMessage], context: ChatContext? = nil, healthConsent: Bool = false, stream: Bool = true) {
        self.messages = messages
        self.context = context
        self.consent = Consent(health: healthConsent)
        self.stream = stream
    }
}

public struct ChatUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
}

public struct ToolCall: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var input: JSONValue
}

/// Answer to `stream: false`.
public struct ChatResponse: Codable, Equatable, Sendable {
    public var text: String
    public var toolUses: [ToolCall]
    public var stopReason: String?
    public var usage: ChatUsage
}

/// One Server-Sent Event of a streamed answer.
public enum ChatEvent: Equatable, Sendable {
    case delta(String)
    /// The model wants a tool. Run it on local data, then post again with a tool_result block.
    case toolUse(ToolCall)
    /// Last event. stopReason "tool_use" means tool calls were sent before it.
    case done(stopReason: String?, usage: ChatUsage)
    /// The model failed after the stream had started.
    case error(ServerError)
}
