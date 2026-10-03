import Foundation

public struct QualityCheck: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var passed: Bool
    /// Concrete hint when failed, e.g. "Odejdź krok do tyłu, nie widzę stóp".
    public var hint: String?
    /// The measured numbers behind the result, e.g. "78% klatek, wymagane 75%". Shown when a recording is rejected, so
    /// the person (and we) can see how far off it was.
    public var detail: String?

    public init(id: String, label: String, passed: Bool, hint: String? = nil, detail: String? = nil) {
        self.id = id
        self.label = label
        self.passed = passed
        self.hint = hint
        self.detail = detail
    }
}

public struct QualityReport: Codable, Equatable, Sendable {
    public var passed: Bool
    public var checks: [QualityCheck]
    /// The one hint shown to the user when `passed` is false.
    public var userHint: String?

    public init(passed: Bool, checks: [QualityCheck], userHint: String? = nil) {
        self.passed = passed
        self.checks = checks
        self.userHint = userHint
    }
}

public struct RepMetrics: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { index }
    public var index: Int
    /// Smallest knee angle in degrees (smaller = deeper).
    public var minKneeAngle: Double
    public var hipBelowKnee: Bool
    /// Torso lean from vertical at the lowest point, degrees.
    public var torsoLeanDegrees: Double
    public var descentSeconds: Double
    public var ascentSeconds: Double

    public init(index: Int, minKneeAngle: Double, hipBelowKnee: Bool, torsoLeanDegrees: Double,
                descentSeconds: Double, ascentSeconds: Double) {
        self.index = index
        self.minKneeAngle = minKneeAngle
        self.hipBelowKnee = hipBelowKnee
        self.torsoLeanDegrees = torsoLeanDegrees
        self.descentSeconds = descentSeconds
        self.ascentSeconds = ascentSeconds
    }
}

public enum FindingSeverity: String, Codable, Sendable {
    case good, minor, major
}

public struct TechniqueFinding: Codable, Equatable, Sendable, Identifiable {
    /// Stable id, e.g. `torso_lean_high`, `depth_ok`.
    public var id: String
    public var title: String
    public var detail: String
    public var severity: FindingSeverity
    public var repsAffected: Int
    public var repsTotal: Int

    public init(id: String, title: String, detail: String, severity: FindingSeverity,
                repsAffected: Int, repsTotal: Int) {
        self.id = id
        self.title = title
        self.detail = detail
        self.severity = severity
        self.repsAffected = repsAffected
        self.repsTotal = repsTotal
    }
}

public struct TechniqueResult: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var exerciseId: String
    public var date: Date
    /// 0...100.
    public var score: Int
    /// e.g. ["depth": 85, "torso": 60, "repeatability": 80, "tempo": 70]
    public var componentScores: [String: Int]
    public var findings: [TechniqueFinding]
    public var reps: [RepMetrics]
    public var substituteExerciseId: String?
    /// True for sample data. The UI must mark it as "Dane przykładowe".
    public var isSimulated: Bool

    public init(id: UUID = UUID(), exerciseId: String, date: Date, score: Int,
                componentScores: [String: Int], findings: [TechniqueFinding], reps: [RepMetrics],
                substituteExerciseId: String? = nil, isSimulated: Bool = false) {
        self.id = id
        self.exerciseId = exerciseId
        self.date = date
        self.score = score
        self.componentScores = componentScores
        self.findings = findings
        self.reps = reps
        self.substituteExerciseId = substituteExerciseId
        self.isSimulated = isSimulated
    }
}
