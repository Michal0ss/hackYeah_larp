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
    private(set) var source: Source
    private(set) var cameraError: String?

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
        self.engine = LiveSetEngine(exerciseId: exercise.id, spec: spec, setIndex: setIndex,
                                    voice: SpeechCoachVoice(), kind: kind, isSimulated: source == .simulation,
                                    trackerConfig: PhaseTrackerConfig(values: ContentRepository.shared.numbers("tempo", "phaseTracker")),
                                    cooldownReps: ContentRepository.shared.numbers("tempo", "policy")["cooldownReps"].map(Int.init))
    }

    func start() {
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
                    for await frame in try await camera.frames() {
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

    func stop() {
        task?.cancel()
        task = nil
        #if os(iOS)
        camera.stop()
        #endif
    }
}
