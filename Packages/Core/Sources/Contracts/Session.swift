import Foundation

// Types of the "coach in the workout" thread (WORKINGPLAN.md, section 5): feedback after a workout and the context
// that tells the coach where in the workout a question was asked. All of it is new; nothing existing changed.
//
// Privacy: `WorkoutContext` carries training data only (numbers from a set, no poses, no video) and NO health data.
// Pain and effort live in `SessionFeedback`, stay on the phone, and reach the model only through a consent-gated tool.

// MARK: - Feedback after a workout

/// Where it hurts. Raw values of the first six match `Onboarding.BodyArea`, so the two can be compared by raw value.
public enum PainArea: String, Codable, Sendable, CaseIterable {
    case knee, shoulder, back, hip, elbow, ankle, neck, wrist, other

    public var title: String {
        switch self {
        case .knee: return "Kolano"
        case .shoulder: return "Bark"
        case .back: return "Plecy"
        case .hip: return "Biodro"
        case .elbow: return "Łokieć"
        case .ankle: return "Kostka"
        case .neck: return "Szyja"
        case .wrist: return "Nadgarstek"
        case .other: return "Inne miejsce"
        }
    }
}

public struct PainReport: Codable, Equatable, Sendable, Identifiable {
    public var id: PainArea { area }
    public var area: PainArea
    /// 1...10. An area is reported only when it is above 0.
    public var intensity: Int

    public init(area: PainArea, intensity: Int) {
        self.area = area
        self.intensity = intensity
    }
}

/// What the user says right after a workout. Kept on the phone (`SessionFeedbackStoring`). A signal for the rule
/// engine and the plan, never a diagnosis.
public struct SessionFeedback: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// `PlannedSession.id` of the session this feedback is about.
    public var sessionId: UUID
    public var date: Date
    /// RPE, 1...10: how hard the session felt (1 = very easy, 10 = maximal effort).
    public var perceivedExertion: Int
    /// 1...5, nil when the user skipped it.
    public var enjoyment: Int?
    public var pain: [PainReport]
    /// Free text typed by the user. Data, never an instruction (treated like any other free text on the server).
    public var note: String?
    public var completedSets: Int
    public var plannedSets: Int
    /// True for sample data. The UI must mark it as "Dane przykładowe".
    public var isSimulated: Bool

    public init(id: UUID = UUID(), sessionId: UUID, date: Date = Date(), perceivedExertion: Int,
                enjoyment: Int? = nil, pain: [PainReport] = [], note: String? = nil,
                completedSets: Int, plannedSets: Int, isSimulated: Bool = false) {
        self.id = id
        self.sessionId = sessionId
        self.date = date
        self.perceivedExertion = perceivedExertion
        self.enjoyment = enjoyment
        self.pain = pain
        self.note = note
        self.completedSets = completedSets
        self.plannedSets = plannedSets
        self.isSimulated = isSimulated
    }

    public var maxPainIntensity: Int { pain.map(\.intensity).max() ?? 0 }
    public var hasPain: Bool { maxPainIntensity > 0 }
}

/// A short text from the coach (after a set or after the workout) and where it came from.
public struct FeedbackText: Codable, Equatable, Sendable {
    public var text: String
    /// True when a language model wrote it, false for the phone's own template (offline, or no consent).
    public var isFromModel: Bool
    /// True for sample data. The UI must mark it as "Dane przykładowe".
    public var isSimulated: Bool

    public init(text: String, isFromModel: Bool = false, isSimulated: Bool = false) {
        self.text = text
        self.isFromModel = isFromModel
        self.isSimulated = isSimulated
    }
}

// MARK: - Context of a question to the coach

/// The screen a question to the coach was asked from.
public enum WorkoutScreen: String, Codable, Sendable, CaseIterable {
    case today, plan, liveSet, setSummary, rest, sessionFeedback, analysis
}

/// A technique or tempo finding without its long description: id, title and how many reps it concerns.
public struct FindingDigest: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var severity: FindingSeverity
    public var repsAffected: Int
    public var repsTotal: Int

    public init(id: String, title: String, severity: FindingSeverity, repsAffected: Int, repsTotal: Int) {
        self.id = id
        self.title = title
        self.severity = severity
        self.repsAffected = repsAffected
        self.repsTotal = repsTotal
    }

    public init(_ finding: TechniqueFinding) {
        self.init(id: finding.id, title: finding.title, severity: finding.severity,
                  repsAffected: finding.repsAffected, repsTotal: finding.repsTotal)
    }
}

/// Numbers from one finished set. Built from `SetSummary`; never contains poses, frames or video.
public struct SetDigest: Codable, Equatable, Sendable {
    /// Most findings kept (technique first, then tempo); the server accepts at most this many.
    public static let maxFindings = 12

    public var setIndex: Int
    public var reps: Int
    public var fullRangeReps: Int
    /// 0...100, nil when technique could not be assessed.
    public var techniqueScore: Int?
    /// 0...100.
    public var tempoScore: Int
    /// Written like "3-1-2-0" (`TempoSpec.label`).
    public var targetTempo: String
    /// Averages over the set, in seconds, rounded to 0.1.
    public var averageDescentSeconds: Double
    public var averageAscentSeconds: Double
    public var framing: FramingRating
    public var findings: [FindingDigest]

    public init(setIndex: Int, reps: Int, fullRangeReps: Int, techniqueScore: Int?, tempoScore: Int,
                targetTempo: String, averageDescentSeconds: Double, averageAscentSeconds: Double,
                framing: FramingRating, findings: [FindingDigest]) {
        self.setIndex = setIndex
        self.reps = reps
        self.fullRangeReps = fullRangeReps
        self.techniqueScore = techniqueScore
        self.tempoScore = tempoScore
        self.targetTempo = targetTempo
        self.averageDescentSeconds = averageDescentSeconds
        self.averageAscentSeconds = averageAscentSeconds
        self.framing = framing
        self.findings = Array(findings.prefix(Self.maxFindings))
    }

    public init(_ summary: SetSummary) {
        func average(_ key: KeyPath<RepTempo, Double>) -> Double {
            guard !summary.reps.isEmpty else { return 0 }
            let mean = summary.reps.map { $0[keyPath: key] }.reduce(0, +) / Double(summary.reps.count)
            return (mean * 10).rounded() / 10
        }
        self.init(setIndex: summary.setIndex, reps: summary.reps.count,
                  fullRangeReps: summary.reps.filter(\.isFullRange).count,
                  techniqueScore: summary.techniqueScore, tempoScore: summary.tempoScore,
                  targetTempo: summary.targetTempo.label,
                  averageDescentSeconds: average(\.eccentric), averageAscentSeconds: average(\.concentric),
                  framing: summary.framing.rating,
                  findings: (summary.techniqueFindings + summary.tempoFindings).map(FindingDigest.init))
    }
}

/// Where in the workout a question to the coach was asked. Sent with the chat request (`ChatContext.workout`), so the
/// coach answers about THIS set instead of in general. Everything is optional except the screen.
public struct WorkoutContext: Codable, Equatable, Sendable {
    public var screen: WorkoutScreen
    /// `PlannedSession.id`.
    public var sessionId: UUID?
    public var exerciseId: String?
    /// 1-based number of the set that was just finished or is about to start.
    public var setIndex: Int?
    public var totalSets: Int?
    public var lastSet: SetDigest?

    public init(screen: WorkoutScreen, sessionId: UUID? = nil, exerciseId: String? = nil, setIndex: Int? = nil,
                totalSets: Int? = nil, lastSet: SetDigest? = nil) {
        self.screen = screen
        self.sessionId = sessionId
        self.exerciseId = exerciseId
        self.setIndex = setIndex
        self.totalSets = totalSets
        self.lastSet = lastSet
    }
}

// MARK: - Sample data

public extension SampleData {
    /// Feedback after the first session of `SampleData.plan` (moderate effort, a little knee discomfort).
    static let sessionFeedback = SessionFeedback(
        sessionId: plan.sessions[0].id,
        perceivedExertion: 7,
        enjoyment: 4,
        pain: [PainReport(area: .knee, intensity: 2)],
        note: "Ostatnie serie przysiadów były ciężkie.",
        completedSets: 9, plannedSets: 10,
        isSimulated: true
    )
}
