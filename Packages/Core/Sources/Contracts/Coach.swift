import Foundation

public enum ChatRole: String, Codable, Sendable {
    case user, coach
}

public struct ChatMessage: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var role: ChatRole
    public var text: String
    public var date: Date
    /// Data the coach used, shown under the answer, e.g. "sen z 7 dni".
    public var sources: [String]

    public init(id: UUID = UUID(), role: ChatRole, text: String, date: Date = Date(), sources: [String] = []) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
        self.sources = sources
    }
}

/// Consent to pass health data (as summaries) to the language model.
public struct DataConsent: Codable, Equatable, Sendable {
    public var granted: Bool
    public var date: Date?

    public init(granted: Bool = false, date: Date? = nil) {
        self.granted = granted
        self.date = date
    }
}

/// Small, always-sent context of a coach conversation. Everything else is fetched through tools.
public struct CoachContext: Codable, Equatable, Sendable {
    public var profile: UserProfile
    public var todayRecommendation: DailyRecommendation

    public init(profile: UserProfile, todayRecommendation: DailyRecommendation) {
        self.profile = profile
        self.todayRecommendation = todayRecommendation
    }
}
