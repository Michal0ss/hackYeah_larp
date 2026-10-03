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
    public let spec: TempoSpec
    public let setIndex: Int
    public let isSimulated: Bool

    private let voice: CoachVoice
    private let assessor: TechniqueAssessing
    private var signal = SquatSignal()
    private var tracker = PhaseTracker()
    private var policy = CoachingPolicy()
    private var cueTask: Task<Void, Never>?

    private var readySince: Double?
    private var unreadySince: Double?
    private var setStart = 0.0
    private var goodFrames = 0
    private var totalFrames = 0
    private var lastHint: String?
    private var lastHintSpokenAt: Date?
    private var bottomFrames: [PoseFrame] = []
    private var repBest: (depth: Double, frame: PoseFrame)?

    public init(exerciseId: String, spec: TempoSpec, setIndex: Int = 1, voice: CoachVoice,
                assessor: TechniqueAssessing = BasicSquatAssessor(), isSimulated: Bool = false,
                trackerConfig: PhaseTrackerConfig = PhaseTrackerConfig(), cooldownReps: Int? = nil) {
        self.exerciseId = exerciseId
        self.spec = spec
        self.setIndex = setIndex
        self.voice = voice
        self.assessor = assessor
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

    /// Skip the framing check (the person knows the framing is fine).
    public func startCalibrationNow() {
        guard stage == .framing else { return }
        stage = .calibrating(progress: 0)
        voice.speak("Stań prosto i nieruchomo", priority: .advice)
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
        cueTask?.cancel()
        currentPhase = nil

        let tempo = TempoScoring.evaluate(reps: reps, spec: spec)
        let technique = assessor.assess(bottomFrames: bottomFrames)
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
        framing = FramingAssessor.assess(frame)
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
        framing = FramingAssessor.assess(frame)
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
            voice.speak("Zaczynaj", priority: .count)
        } else if case let .calibrating(progress) = signal.stage {
            stage = .calibrating(progress: progress)
        }
    }

    private func handleActive(_ frame: PoseFrame) {
        let report = FramingAssessor.assess(frame, checkSize: false)
        totalFrames += 1
        if report.ready { goodFrames += 1 } else { lastHint = report.hint }
        framing = report

        guard let depth = signal.depth(for: frame) else { return }
        latestDepth = depth
        if tracker.phase != nil, depth > (repBest?.depth ?? -1) { repBest = (depth, frame) }

        for event in tracker.update(time: frame.time, depth: depth) {
            switch event {
            case let .phaseStarted(phase, _):
                currentPhase = phase
                phaseStartedAt = Date()
                scheduleCues(for: phase, isFirstRep: tracker.repCount == 0)
            case var .repCompleted(rep):
                rep.startedAt -= setStart
                reps.append(rep)
                if let best = repBest { bottomFrames.append(best.frame) }
                repBest = nil
                cueTask?.cancel()
                currentPhase = nil
                if let advice = policy.advice(after: rep, spec: spec) {
                    lastCue = advice
                    voice.speak(advice, priority: .advice)
                }
            case .idleTimeout:
                if !reps.isEmpty { finish() }
            }
        }
    }

    // MARK: - Voice

    private func scheduleCues(for phase: RepPhase, isFirstRep: Bool) {
        cueTask?.cancel()
        let cues = CuePlanner.cues(for: phase, spec: spec, isFirstRep: isFirstRep)
        guard !cues.isEmpty else { return }
        cueTask = Task { [weak self] in
            let start = ContinuousClock.now
            for cue in cues {
                try? await Task.sleep(until: start.advanced(by: .seconds(cue.offset)), clock: .continuous)
                if Task.isCancelled { return }
                self?.say(cue.text)
            }
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
