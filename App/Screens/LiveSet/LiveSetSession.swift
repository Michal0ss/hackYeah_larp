import SwiftUI
import Observation
import AVFoundation
import Contracts
import Content
import LiveSet

/// Owns the engine and its frame source (camera on a device, simulated squat in the simulator).
@MainActor
@Observable
final class LiveSetSession {
    enum Source: String, CaseIterable {
        case camera = "Kamera"
        case simulation = "Symulacja"
    }

    let engine: LiveSetEngine
    let exercise: ExerciseItem
    let kind: MovementKind
    let spec: TempoSpec
    let setIndex: Int
    /// What the assessment adapted to the person (mobility, level, an earlier injury), shown on the summary.
    let contextNotes: [String]
    private(set) var source: Source
    private(set) var cameraError: String?
    /// Which camera is used. The choice is remembered for the next set (every set is a new session).
    private(set) var isFrontCamera: Bool
    /// Bumped when the camera was switched, so the preview refreshes.
    private(set) var cameraRevision = 0
    private static let frontCameraKey = "forma.liveSet.frontCamera"

    #if os(iOS)
    let camera = CameraPoseSource()
    #endif
    private var task: Task<Void, Never>?

    init(exercise: ExerciseItem, spec: TempoSpec, setIndex: Int) {
        self.exercise = exercise
        let kind = MovementKind.kind(for: exercise) ?? .squat
        self.kind = kind
        self.spec = spec
        self.setIndex = setIndex
        #if targetEnvironment(simulator)
        let source = Source.simulation
        #else
        let source = Source.camera
        #endif
        self.source = source
        self.isFrontCamera = UserDefaults.standard.bool(forKey: Self.frontCameraKey)
        let base = AngleReference(values: ContentRepository.shared.numbers("scoring", "angles"))
        // The same context and rules as a recorded clip is scored with, so a set and a clip are judged alike.
        let context = TechniqueContextStore.shared.current()
        let rules = ContextRules(values: ContentRepository.shared.numbers("scoring", "context"))
        let adjustment = context.adjustment(for: kind, base: base, rules: rules)
        self.contextNotes = adjustment.notes
        let reference = adjustment.reference
        self.engine = LiveSetEngine(exerciseId: exercise.id, spec: spec, setIndex: setIndex,
                                    voice: BankedCoachVoice(), kind: kind,
                                    assessor: ContextualAssessor(kind: kind, base: base, context: context, rules: rules),
                                    isSimulated: source == .simulation,
                                    trackerConfig: PhaseTrackerConfig(values: ContentRepository.shared.numbers("tempo", "phaseTracker")),
                                    cooldownReps: ContentRepository.shared.numbers("tempo", "policy")["cooldownReps"].map(Int.init),
                                    reference: reference,
                                    minBend: ContentRepository.shared.numbers("scoring", "clip")["minAngleChange"] ?? 20)
    }

    func start() {
        #if os(iOS)
        // The switch finishes on the capture queue; the preview then needs its rotation again.
        camera.onSwitched = { [weak self] in MainActor.assumeIsolated { self?.cameraRevision += 1 } }
        #endif
        engine.prepare()
        task?.cancel()
        cameraError = nil
        switch source {
        case .simulation:
            task = Task { [engine] in
                for await frame in SimulatedSquat(kind: kind).stream() {
                    engine.ingest(frame)
                }
                if engine.stage != .summary { engine.finish() }
            }
        case .camera:
            #if os(iOS)
            task = Task { [engine, camera] in
                do {
                    for await frame in try await camera.frames(position: isFrontCamera ? .front : .back) {
                        engine.ingest(frame)
                    }
                } catch CameraPoseSource.CameraError.denied {
                    self.cameraError = "Brak dostępu do kamery. Włącz go w Ustawieniach."
                } catch {
                    self.cameraError = "Nie udało się uruchomić kamery."
                }
            }
            #endif
        }
    }

    /// "Obróć kamerę": back <-> front. Possible until the first repetition: the setup then starts over, because the
    /// calibration belongs to one view. After that a switch would mix two views into one set.
    var canFlipCamera: Bool { engine.canRestartSetup }

    func flipCamera() {
        guard canFlipCamera else { return }
        isFrontCamera.toggle()
        engine.restartSetup()
        UserDefaults.standard.set(isFrontCamera, forKey: Self.frontCameraKey)
        #if os(iOS)
        if source == .camera { camera.switchCamera(to: isFrontCamera ? .front : .back) }
        #endif
        cameraRevision += 1
    }

    func stop() {
        task?.cancel()
        task = nil
        #if os(iOS)
        camera.stop()
        #endif
    }
}
