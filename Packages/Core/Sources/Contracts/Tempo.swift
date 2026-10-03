import Foundation

/// Target tempo of one repetition, in seconds per phase.
/// Written like "3-1-2-0": eccentric - pause at the bottom - concentric - pause at the top.
public struct TempoSpec: Codable, Equatable, Sendable {
    public var eccentric: Double
    public var bottomPause: Double
    public var concentric: Double
    public var topPause: Double

    public init(eccentric: Double, bottomPause: Double, concentric: Double, topPause: Double = 0) {
        self.eccentric = eccentric
        self.bottomPause = bottomPause
        self.concentric = concentric
        self.topPause = topPause
    }

    /// Controlled tempo used as the default: 3 s down, 1 s pause, 2 s up.
    public static let controlled = TempoSpec(eccentric: 3, bottomPause: 1, concentric: 2, topPause: 0)

    public var label: String {
        func s(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
        return "\(s(eccentric))-\(s(bottomPause))-\(s(concentric))-\(s(topPause))"
    }
}

public enum RepPhase: String, Codable, Sendable, CaseIterable {
    case eccentric, bottomPause, concentric, topPause

    public var title: String {
        switch self {
        case .eccentric: return "W dół"
        case .bottomPause: return "Pauza"
        case .concentric: return "W górę"
        case .topPause: return "Góra"
        }
    }
}

/// Measured timing of one repetition.
public struct RepTempo: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { index }
    public var index: Int
    /// Seconds from the start of the set.
    public var startedAt: Double
    public var eccentric: Double
    public var bottomPause: Double
    public var concentric: Double
    /// Rest at the top before this repetition started (0 for the first one).
    public var topPauseBefore: Double
    /// Deepest point reached, in torso lengths below the standing position.
    public var peakDepth: Double
    /// False when the movement did not reach the minimum range.
    public var isFullRange: Bool

    public init(index: Int, startedAt: Double, eccentric: Double, bottomPause: Double, concentric: Double,
                topPauseBefore: Double, peakDepth: Double, isFullRange: Bool) {
        self.index = index
        self.startedAt = startedAt
        self.eccentric = eccentric
        self.bottomPause = bottomPause
        self.concentric = concentric
        self.topPauseBefore = topPauseBefore
        self.peakDepth = peakDepth
        self.isFullRange = isFullRange
    }

    public var totalSeconds: Double { eccentric + bottomPause + concentric }
}

public enum FramingRating: String, Codable, Sendable {
    case good, fair, poor

    public var title: String {
        switch self {
        case .good: return "Dobra"
        case .fair: return "Średnia"
        case .poor: return "Słaba"
        }
    }
}

/// How well the person was framed during the set (shown as "Jakość" between sets).
public struct FramingSummary: Codable, Equatable, Sendable {
    public var rating: FramingRating
    /// Share of frames in which all key joints were visible, 0...1.
    public var goodFrameRatio: Double
    public var hint: String?

    public init(rating: FramingRating, goodFrameRatio: Double, hint: String? = nil) {
        self.rating = rating
        self.goodFrameRatio = goodFrameRatio
        self.hint = hint
    }
}

/// Everything shown between sets: technique, quality of the recording and tempo.
public struct SetSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var exerciseId: String
    public var date: Date
    public var setIndex: Int
    public var targetTempo: TempoSpec
    public var reps: [RepTempo]
    /// 0...100, how close the tempo was to the target.
    public var tempoScore: Int
    public var tempoFindings: [TechniqueFinding]
    /// 0...100, nil when technique could not be assessed.
    public var techniqueScore: Int?
    public var techniqueFindings: [TechniqueFinding]
    public var framing: FramingSummary
    public var isSimulated: Bool

    public init(id: UUID = UUID(), exerciseId: String, date: Date = Date(), setIndex: Int, targetTempo: TempoSpec,
                reps: [RepTempo], tempoScore: Int, tempoFindings: [TechniqueFinding], techniqueScore: Int?,
                techniqueFindings: [TechniqueFinding], framing: FramingSummary, isSimulated: Bool = false) {
        self.id = id
        self.exerciseId = exerciseId
        self.date = date
        self.setIndex = setIndex
        self.targetTempo = targetTempo
        self.reps = reps
        self.tempoScore = tempoScore
        self.tempoFindings = tempoFindings
        self.techniqueScore = techniqueScore
        self.techniqueFindings = techniqueFindings
        self.framing = framing
        self.isSimulated = isSimulated
    }
}
