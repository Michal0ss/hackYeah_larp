import Foundation
import Contracts

public enum HealthAccessChoice: String, Codable, Sendable {
    /// The user allowed Apple Health access.
    case granted
    /// The user chose to continue with simulated data.
    case sampleData
}

public struct OnboardingResult: Equatable, Sendable {
    public var profile: UserProfile
    /// Stays on the phone. Never passed to the plan generator or to the language model.
    public var health: HealthHistory
    public var plan: TrainingPlan
    public var healthAccess: HealthAccessChoice
    public var completedAt: Date

    public init(profile: UserProfile, health: HealthHistory, plan: TrainingPlan,
                healthAccess: HealthAccessChoice, completedAt: Date = Date()) {
        self.profile = profile
        self.health = health
        self.plan = plan
        self.healthAccess = healthAccess
        self.completedAt = completedAt
    }
}
