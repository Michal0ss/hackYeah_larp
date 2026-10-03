import Foundation
import Contracts

/// Everything the user chooses during onboarding, before it becomes a `UserProfile`.
public struct OnboardingDraft: Equatable, Sendable {
    public static let dayOptions = [2, 3, 4, 5]
    public static let minuteOptions = [30, 45, 60, 75]

    public var goal: TrainingGoal = .strength
    public var level: TrainingLevel = .intermediate
    public var daysPerWeek = 4
    public var sessionMinutes = 45
    public var gear: Set<GearItem> = []
    /// Free text ("czego unikać"). We do not judge it medically.
    public var avoid = ""
    public var health = HealthHistory()

    public init() {}

    // MARK: - Editing

    /// Only values offered by the UI are accepted.
    public mutating func setDays(_ days: Int) {
        if Self.dayOptions.contains(days) { daysPerWeek = days }
    }

    public mutating func setMinutes(_ minutes: Int) {
        if Self.minuteOptions.contains(minutes) { sessionMinutes = minutes }
    }

    /// "Bez sprzętu" excludes the others, and the other way round.
    public mutating func toggleGear(_ item: GearItem) {
        if gear.contains(item) {
            gear.remove(item)
        } else if item == .none {
            gear = [.none]
        } else {
            gear.remove(.none)
            gear.insert(item)
        }
    }

    // MARK: - Result

    /// Nothing ticked means no equipment.
    public var resolvedGear: [GearItem] {
        let chosen = GearItem.allCases.filter(gear.contains)
        return chosen.isEmpty ? [.none] : chosen
    }

    /// The profile that goes to the plan generator and (as part of the coach context) to the model.
    /// It carries no health history, only the derived movements to leave out and the easy-start flag.
    public func makeProfile() -> UserProfile {
        let gearList = resolvedGear
        return UserProfile(
            goal: goal, level: level, daysPerWeek: daysPerWeek, sessionMinutes: sessionMinutes,
            equipment: Equipment.resolve(from: gearList),
            avoid: avoid.trimmingCharacters(in: .whitespacesAndNewlines),
            gear: gearList,
            avoidTags: health.omitTags,
            easyStart: health.suggestsConsultation || health.hasReportedCondition
        )
    }
}
