import Contracts
import Foundation

/// The daily step goal. The trainer (the coach in the chat) sets it; until then the app starts from a modest goal that
/// fits the person's level and aim. Kept on the phone. A target for the person, not a medical recommendation.
public struct StepGoal: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// Worked out by the app from the profile, nobody has set a goal yet.
        case starting
        /// Set by the trainer in the chat, at the person's request or with their agreement.
        case coach
    }

    public static let range = 2_000...30_000

    public var steps: Int
    public var source: Source
    /// One short sentence from the trainer: why this number.
    public var reason: String?
    public var date: Date

    public init(steps: Int, source: Source, reason: String? = nil, date: Date = Date()) {
        self.steps = min(max(steps, Self.range.lowerBound), Self.range.upperBound)
        self.source = source
        self.reason = reason
        self.date = date
    }

    /// A modest first goal: 6 000 steps for a beginner and 8 000 otherwise, a little less for returning to movement
    /// and a little more for general fitness.
    public static func starting(for profile: UserProfile, now: Date = Date()) -> StepGoal {
        var steps = profile.level == .beginner ? 6_000 : 8_000
        switch profile.goal {
        case .returnToMovement: steps -= 1_000
        case .fitness: steps += 1_000
        default: break
        }
        return StepGoal(steps: steps, source: .starting, reason: nil, date: now)
    }

    /// 0...1 (above 1 means the goal was passed).
    public func progress(steps done: Int) -> Double {
        steps > 0 ? Double(done) / Double(steps) : 0
    }
}

/// Where the goal is kept (`UserDefaults`, one small JSON value).
public final class StepGoalStore: @unchecked Sendable {
    public static let standard = StepGoalStore()

    private let defaults: UserDefaults
    private let key = "forma.stepGoal"
    private let lock = NSLock()

    /// Called after the goal changed (from whatever thread made it), so the screens can refresh. Set once at start-up.
    public var onChange: (@Sendable () -> Void)?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The goal set by the trainer, nil until there is one.
    public var current: StepGoal? {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(StepGoal.self, from: data)
    }

    /// The trainer's goal, or the starting goal for this profile.
    public func goal(for profile: UserProfile) -> StepGoal {
        current ?? .starting(for: profile)
    }

    @discardableResult
    public func set(_ goal: StepGoal) -> StepGoal {
        defer { onChange?() }
        lock.lock(); defer { lock.unlock() }
        if let data = try? JSONEncoder().encode(goal) { defaults.set(data, forKey: key) }
        return goal
    }

    /// Forgets the goal (the user deleted all data).
    public func clear() {
        defer { onChange?() }
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: key)
    }
}
