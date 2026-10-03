import Foundation
import Observation
import Contracts

/// Runs one live set: checks framing, calibrates, tracks repetitions from pose frames,
/// speaks the tempo counts and corrections, and builds the summary shown between sets.
/// Feed it frames with `ingest(_:)`, from the camera or from `SimulatedSquat`.
@MainActor
@Observable
public final class LiveSetEngine {
    public enum Stage: Equatable {
        case framing
        case calibrating(progress: Double)
        case active
        case summary
    }

    // Public state for the UI.
    public private(set) var stage: Stage = .framing
    public private(set) var framing: FramingReport = FramingAssessor.assess(nil)
    public private(set) var currentPhase: RepPhase?
    /// Wall-clock start of the current phase, for timers in the UI.
    public private(set) var phaseStartedAt: Date?
    public private(set) var reps: [RepTempo] = []
    public private(set) var lastCue: String?
    public private(set) var latestFrame: PoseFrame?
    public private(set) var summary: SetSummary?

    /// The main joint angle of the exercise (knee of a squat, elbow of a push-up and a pull-up) in the latest frame,
    /// aspect corrected. Nil while the joints are not visible.
    public private(set) var liveAngle: Double?
    /// The band of that angle expected at the working end of the movement (from `AngleReference`).
    public let targetBand: ClosedRange<Double>

    /// The verdict on the repetition that has just ended, against the same ranges the summary uses.
    public struct RepVerdict: Equatable, Sendable {
        public var index: Int
        /// The angle at the working end of that repetition.
        public var angle: Double?
        public var isGood: Bool
        /// "Technika w normie" or the title of the first thing that is off ("Za płytko").
        public var text: String
    }
    public private(set) var lastVerdict: RepVerdict?

    // Diagnostics for testing on a real phone (see PoseDiagnostics and the diagnostics panel in the app).
    /// Frames per second the pose stream is delivering (smoothed).
    public private(set) var framesPerSecond = 0.0
    /// Depth in torso lengths after calibration, nil before.
    public private(set) var latestDepth: Double?
    /// When true every incoming frame is kept in `recordedFrames` (joint numbers only, never video).
    public var recordsFrames = false
    public private(set) var recordedFrames: [PoseFrame] = []
    private var lastFrameTime: Double?

    public let exerciseId: String
    public let kind: MovementKind
    public let spec: TempoSpec
    public let setIndex: Int
    public let isSimulated: Bool

    private let voice: CoachVoice
    private let assessor: TechniqueAssessing
    private var signal: SquatSignal
    private var tracker = PhaseTracker()
    private var policy = CoachingPolicy()

    private var readySince: Double?
    private var unreadySince: Double?
    private var setStart = 0.0
    private var goodFrames = 0
    private var totalFrames = 0
    private var lastHint: String?
    private var lastHintSpokenAt: Date?
    private var bottomFrames: [PoseFrame] = []
    private var startFrames: [PoseFrame] = []
    /// The frames since the last repetition ended (the start position of the next one is in there), capped.
    private var recentFrames: [PoseFrame] = []
    private static let maxRecentFrames = 450
    private var repBest: (depth: Double, frame: PoseFrame)?

    public init(exerciseId: String, spec: TempoSpec, setIndex: Int = 1, voice: CoachVoice,
                kind: MovementKind = .squat, assessor: TechniqueAssessing? = nil, isSimulated: Bool = false,
                trackerConfig: PhaseTrackerConfig = PhaseTrackerConfig(), cooldownReps: Int? = nil,
                reference: AngleReference = AngleReference()) {
        self.targetBand = kind.targetBand(reference)
        self.exerciseId = exerciseId
        self.kind = kind
        self.signal = SquatSignal(kind: kind)
        self.spec = spec
        self.setIndex = setIndex
        self.voice = voice
        self.assessor = assessor ?? kind.assessor(reference: reference)
        self.isSimulated = isSimulated
        self.tracker = PhaseTracker(config: trackerConfig)
        if let cooldownReps { self.policy.cooldownReps = cooldownReps }
    }

    public var headphonesConnected: Bool { voice.headphonesConnected }

    /// Smoothed depth and vertical speed (torso lengths and torso lengths per second) as the phase tracker sees them.
    public var trackerDepth: Double { tracker.smoothedDepth }
    public var trackerVelocity: Double { tracker.velocity }

    /// The recorded pose frames as JSON, for sharing as test fixtures. Nil when nothing was recorded.
    public func recordedPoseJSON() -> Data? {
        guard !recordedFrames.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(recordedFrames)
    }

    public func prepare() {
        voice.prepare()
    }

    /// True while the setup can still be started over: before the first repetition of the set.
    public var canRestartSetup: Bool {
        switch stage {
        case .framing, .calibrating: return true
        case .active: return reps.isEmpty
        case .summary: return false
        }
    }

    /// Starts the setup over: back to the framing check and a fresh calibration. Used after the camera was switched,
    /// because the calibration (standing height, body size) belongs to one view. A set that already counts
    /// repetitions keeps its view, so this does nothing then.
    public func restartSetup() {
        guard canRestartSetup else { return }
        currentPhase = nil
        phaseStartedAt = nil
        latestDepth = nil
        readySince = nil
        unreadySince = nil
        repBest = nil
        bottomFrames = []
        startFrames = []
        recentFrames = []
        lastVerdict = nil
        liveAngle = nil
        goodFrames = 0
        totalFrames = 0
        signal.reset()
        tracker.reset()
        stage = .framing
    }

    /// Skip the framing check (the person knows the framing is fine).
    public func startCalibrationNow() {
        guard stage == .framing else { return }
        stage = .calibrating(progress: 0)
        voice.speak(kind.calibrationSpoken, priority: .advice)
    }

    public func ingest(_ frame: PoseFrame) {
        if let last = lastFrameTime, frame.time > last {
            let instant = 1 / (frame.time - last)
            framesPerSecond = framesPerSecond == 0 ? instant : framesPerSecond * 0.9 + instant * 0.1
        }
        lastFrameTime = frame.time
        if recordsFrames, recordedFrames.count < 30_000 { recordedFrames.append(frame) }
        latestFrame = frame
        switch stage {
        case .framing: handleFraming(frame)
        case .calibrating: handleCalibration(frame)
        case .active: handleActive(frame)
        case .summary: break
        }
    }

    /// End the set (button or long idle). Builds the summary.
    public func finish() {
        guard stage == .active || stage == .calibrating(progress: 0) || stage == .framing else { return }
        currentPhase = nil

        let tempo = TempoScoring.evaluate(reps: reps, spec: spec)
        let technique = assessor.assess(bottomFrames: bottomFrames, startFrames: startFrames)
        let framingSummary = FramingAssessor.summarize(goodFrames: goodFrames, totalFrames: totalFrames, lastHint: lastHint)
        summary = SetSummary(exerciseId: exerciseId, setIndex: setIndex, targetTempo: spec, reps: reps,
                             tempoScore: tempo.score, tempoFindings: tempo.findings,
                             techniqueScore: technique.score, techniqueFindings: technique.findings,
                             framing: framingSummary, isSimulated: isSimulated)
        stage = .summary
        voice.speak(reps.isEmpty ? "Nie wykryłem powtórzeń" : "Koniec serii. \(repsLabel(reps.count)).", priority: .count)
        voice.finish()
    }

    // MARK: - Stages

    private func handleFraming(_ frame: PoseFrame) {
        framing = FramingAssessor.assess(frame, kind: kind)
        if framing.ready {
            lastHint = nil
            let since = readySince ?? frame.time
            readySince = since
            if frame.time - since >= 1.0 { startCalibrationNow() }
        } else {
            readySince = nil
            lastHint = framing.hint
            speakHintIfNeeded(framing.hint)
        }
    }

    private func handleCalibration(_ frame: PoseFrame) {
        framing = FramingAssessor.assess(frame, kind: kind)
        if framing.ready { unreadySince = nil } else {
            let since = unreadySince ?? frame.time
            unreadySince = since
            if frame.time - since > 1.5 {
                stage = .framing
                readySince = nil
                unreadySince = nil
                signal.reset()
                return
            }
        }
        if signal.depth(for: frame) != nil, signal.stage == .ready {
            setStart = frame.time
            tracker.reset()
            stage = .active
            voice.signalSetStart()
        } else if case let .calibrating(progress) = signal.stage {
            stage = .calibrating(progress: progress)
        }
    }

    private func handleActive(_ frame: PoseFrame) {
        let report = FramingAssessor.assess(frame, kind: kind, checkSize: false)
        totalFrames += 1
        if report.ready { goodFrames += 1 } else { lastHint = report.hint }
        framing = report

        liveAngle = kind.primaryAngle(in: frame, minConfidence: 0.2)
        recentFrames.append(frame)
        if recentFrames.count > Self.maxRecentFrames { recentFrames.removeFirst(recentFrames.count - Self.maxRecentFrames) }

        guard let depth = signal.depth(for: frame) else { return }
        latestDepth = depth
        if tracker.phase != nil, depth > (repBest?.depth ?? -1) { repBest = (depth, frame) }

        for event in tracker.update(time: frame.time, depth: depth) {
            switch event {
            case let .phaseStarted(tracked, _):
                let phase = kind.exercisePhase(tracked)
                currentPhase = phase
                phaseStartedAt = Date()
                announcePhase(phase)
            case var .repCompleted(rep):
                rep = kind.exerciseRep(rep)
                rep.startedAt -= setStart
                reps.append(rep)
                if let best = repBest {
                    // The frames the technique is judged on: the working end and the start position of this repetition,
                    // each a robust pick near the moment (not one glitchy frame), the way a recorded clip does it.
                    bottomFrames.append(kind.representativeFrame(in: recentFrames, around: best.frame.time, radius: 0.2, wantMin: true)
                                        ?? best.frame)
                    // The tracker notices the movement a few tenths after it began, so the start position is looked for
                    // from before that moment.
                    let start = rep.startedAt + setStart - 0.4
                    let top = kind.representativeFrame(in: recentFrames, around: start, radius: 0.55, wantMin: false)
                    if let top { startFrames.append(top) }
                    if let bottom = bottomFrames.last { lastVerdict = verdict(index: reps.count, bottom: bottom, start: top) }
                }
                repBest = nil
                recentFrames.removeAll(keepingCapacity: true)
                currentPhase = nil
                // Shown on screen (LiveSetView) but not spoken: the only things said live are the
                // phase cues below, so corrections don't talk over the next "w dół"/"w górę".
                if let advice = policy.advice(after: rep, spec: spec) {
                    lastCue = advice
                }
            case .idleTimeout:
                if !reps.isEmpty { finish() }
            }
        }
    }

    /// The repetition judged on its own, with the same assessor and ranges as the summary at the end of the set.
    private func verdict(index: Int, bottom: PoseFrame, start: PoseFrame?) -> RepVerdict {
        let assessment = assessor.assess(bottomFrames: [bottom], startFrames: start.map { [$0] } ?? [])
        let issue = assessment.findings.first { $0.severity != .good }
        return RepVerdict(index: index, angle: kind.primaryAngle(in: bottom, minConfidence: 0.15),
                          isGood: issue == nil, text: issue?.title ?? "Technika w normie")
    }

    // MARK: - Voice

    /// The only things said while a rep is in progress: the start of the lifting phase and the
    /// start of the lowering phase, once each, right as they begin. No per-second counting and no
    /// announcement for the pauses — a quiet coach is easier to work out to than a constant one.
    private func announcePhase(_ phase: RepPhase) {
        switch phase {
        case .eccentric, .concentric: say(CuePlanner.label(of: phase))
        case .bottomPause, .topPause: break
        }
    }

    private func say(_ text: String) {
        lastCue = text
        voice.speak(text, priority: .count)
    }

    private func speakHintIfNeeded(_ hint: String?) {
        guard let hint else { return }
        let now = Date()
        if let last = lastHintSpokenAt, now.timeIntervalSince(last) < 6 { return }
        lastHintSpokenAt = now
        voice.speak(hint, priority: .advice)
    }
}
