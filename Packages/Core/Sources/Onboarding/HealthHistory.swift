import Foundation
import Contracts

// Health history and the pre-activity screening. This stays ON THE PHONE (see `OnboardingStorage`).
// Only what `OnboardingDraft.makeProfile()` derives from it (`avoidTags`, `easyStart`) reaches the plan
// generator and the language model. Nothing here is a diagnosis: the app only decides what to leave out of
// the plan and when to say "warto rozważyć konsultację".

public enum BodyArea: String, Codable, CaseIterable, Sendable {
    case knee, shoulder, back, hip, elbow, ankle

    public var title: String {
        switch self {
        case .knee: return "Kolano"
        case .shoulder: return "Bark"
        case .back: return "Plecy"
        case .hip: return "Biodro"
        case .elbow: return "Łokieć"
        case .ankle: return "Kostka"
        }
    }
}

public enum InjuryRecency: String, Codable, CaseIterable, Sendable {
    case recent, mid, old

    public var title: String {
        switch self {
        case .recent: return "Do 3 mies."
        case .mid: return "3–12 mies."
        case .old: return "Ponad rok"
        }
    }

    /// Used in the summary line: "Kolano · ponad rok temu".
    public var summary: String {
        switch self {
        case .recent: return "do 3 mies. temu"
        case .mid: return "3–12 mies. temu"
        case .old: return "ponad rok temu"
        }
    }
}

public enum HealthCondition: String, Codable, CaseIterable, Sendable {
    case cardiovascular, diabetes, lungs, joints, postSurgery, pregnancy

    public var title: String {
        switch self {
        case .cardiovascular: return "Układ krążenia"
        case .diabetes: return "Cukrzyca"
        case .lungs: return "Astma lub płuca"
        case .joints: return "Choroby stawów"
        case .postSurgery: return "Po operacji (do 12 mies.)"
        case .pregnancy: return "Ciąża lub połóg"
        }
    }
}

/// The six standard screening questions. A "yes" to most of them suggests talking to a doctor first.
public enum ScreeningQuestion: Int, CaseIterable, Sendable {
    case supervisedOnly, chestPain, dizziness, jointOrBone, heartMedication, otherReason

    public var text: String {
        switch self {
        case .supervisedOnly: return "Lekarz zalecił ćwiczenia tylko pod nadzorem"
        case .chestPain: return "Ból lub ucisk w klatce piersiowej przy wysiłku"
        case .dizziness: return "Zawroty głowy lub omdlenia"
        case .jointOrBone: return "Staw lub kość, które pogarszają się przy ruchu"
        case .heartMedication: return "Leki na ciśnienie lub serce"
        case .otherReason: return "Inny powód, dla którego nie powinno się ćwiczyć"
        }
    }

    /// "Yes" suggests a consultation. The joint or bone question only adapts the plan.
    public var suggestsConsultation: Bool { self != .jointOrBone }
}

public enum ScreeningResult: Equatable, Sendable {
    /// Some questions are unanswered and nothing calls for caution yet.
    case incomplete
    case clear
    /// The plan leaves these movements out.
    case adapt(omit: [MovementTag])
    case consult(omit: [MovementTag])
}

public struct HealthHistory: Codable, Equatable, Sendable {
    public var injuries: Set<BodyArea>
    public var injuryRecency: InjuryRecency
    public var conditions: Set<HealthCondition>
    /// The user explicitly ticked "Nic z powyższych".
    public var noConditions: Bool
    /// Answers to the six screening questions in `ScreeningQuestion` order. nil = not answered.
    public var answers: [Bool?]

    public init(injuries: Set<BodyArea> = [], injuryRecency: InjuryRecency = .old,
                conditions: Set<HealthCondition> = [], noConditions: Bool = false,
                answers: [Bool?] = Array(repeating: nil, count: ScreeningQuestion.allCases.count)) {
        self.injuries = injuries
        self.injuryRecency = injuryRecency
        self.conditions = conditions
        self.noConditions = noConditions
        self.answers = answers.count == ScreeningQuestion.allCases.count
            ? answers : Array(repeating: nil, count: ScreeningQuestion.allCases.count)
    }

    // MARK: - Editing

    public mutating func toggleInjury(_ area: BodyArea) {
        if injuries.contains(area) { injuries.remove(area) } else { injuries.insert(area) }
    }

    /// Ticking a condition clears "Nic z powyższych".
    public mutating func toggleCondition(_ condition: HealthCondition) {
        if conditions.contains(condition) {
            conditions.remove(condition)
        } else {
            conditions.insert(condition)
            noConditions = false
        }
    }

    /// "Nic z powyższych" clears the conditions.
    public mutating func selectNoConditions() {
        conditions = []
        noConditions = true
    }

    public mutating func answer(_ question: ScreeningQuestion, _ yes: Bool) {
        answers[question.rawValue] = yes
    }

    public func answer(for question: ScreeningQuestion) -> Bool? {
        answers[question.rawValue]
    }

    // MARK: - Derived

    public var allAnswered: Bool { !answers.contains { $0 == nil } }

    /// At least one "yes" to a question that suggests talking to a doctor.
    public var suggestsConsultation: Bool {
        ScreeningQuestion.allCases.contains { $0.suggestsConsultation && answer(for: $0) == true }
    }

    /// Movements to leave out of the plan, in a stable order.
    public var omitTags: [MovementTag] {
        var tags = Set<MovementTag>()
        if injuries.contains(.knee) || injuries.contains(.ankle) { tags.insert(.jumps) }
        if injuries.contains(.knee) { tags.insert(.deepLunges) }
        if injuries.contains(.shoulder) { tags.insert(.overheadPress) }
        if injuries.contains(.back) { tags.insert(.barbellDeadlift) }
        if injuries.contains(.hip) { tags.insert(.deepSquats) }
        if injuries.contains(.elbow) { tags.insert(.loadedPushups) }
        if tags.isEmpty, answer(for: .jointOrBone) == true { tags.insert(.jumps) }
        return MovementTag.allCases.filter(tags.contains)
    }

    public var result: ScreeningResult {
        let omit = omitTags
        if suggestsConsultation { return .consult(omit: omit) }
        if !allAnswered { return .incomplete }
        return omit.isEmpty ? .clear : .adapt(omit: omit)
    }

    /// Any reported condition: the first weeks are planned lighter ("pomaga dobrać intensywność").
    public var hasReportedCondition: Bool { !conditions.isEmpty }

    /// Nothing was provided at all.
    public var isEmpty: Bool {
        injuries.isEmpty && conditions.isEmpty && !noConditions && answers.allSatisfy { $0 == nil }
    }

    public var injurySummary: String {
        guard !injuries.isEmpty else { return "Nic nie zaznaczono" }
        let names = BodyArea.allCases.filter(injuries.contains).map(\.title).joined(separator: ", ")
        return "\(names) · \(injuryRecency.summary)"
    }

    public var conditionSummary: String {
        if noConditions { return "Nic z powyższych" }
        let names = HealthCondition.allCases.filter(conditions.contains).map(\.title)
        return names.isEmpty ? "Nie podano" : names.joined(separator: ", ")
    }
}
