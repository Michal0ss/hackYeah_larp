import Foundation

/// What the health history says about where a movement should not be pushed. Read on the phone to widen the range the
/// technique assessment asks for (`TechniqueContext`); it is not sent anywhere and it is not a diagnosis.
public extension HealthHistory {
    /// A knee, hip or ankle injury that is not old (up to a year ago): a squat is not pushed to full depth.
    var hasRecentLowerBodyInjury: Bool {
        injuryRecency != .old && !injuries.isDisjoint(with: [.knee, .hip, .ankle])
    }

    /// A shoulder or elbow injury that is not old: a push-up, a pull-up and a dip are not pushed to full range.
    var hasRecentUpperBodyInjury: Bool {
        injuryRecency != .old && !injuries.isDisjoint(with: [.shoulder, .elbow])
    }
}
