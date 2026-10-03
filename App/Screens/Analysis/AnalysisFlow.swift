import Analysis
import Content
import Contracts
import Foundation
import Observation

/// Drives the six analysis screens (PROJECT.md 5.3): exercise -> framing instructions -> capture ->
/// quality gate -> processing -> result. Pure state; the views only read it and call its actions.
@MainActor
@Observable
final class AnalysisModel {
    enum Step: Equatable {
        case exercise, framing, capture, quality, processing, result
    }

    private(set) var step: Step = .exercise
    var selectedExercise: ExerciseItem?
    private(set) var videoURL: URL?
    private(set) var frames: [PoseFrame] = []
    private(set) var qualityReport: QualityReport?
    private(set) var result: TechniqueResult?
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    var canGoBack: Bool {
        switch step {
        case .exercise, .processing, .result: return false
        case .framing, .capture, .quality: return true
        }
    }

    func choose(_ exercise: ExerciseItem) {
        selectedExercise = exercise
        step = .framing
    }

    func proceedFromFraming() { step = .capture }

    func back() {
        switch step {
        case .exercise, .processing, .result: break
        case .framing: step = .exercise
        case .capture: step = .framing
        case .quality: retryCapture()
        }
    }

    /// A video was recorded or picked from the gallery; run the quality gate on it.
    func use(video url: URL) {
        videoURL = url
        step = .quality
        Task { await runQualityCheck() }
    }

    func retryCapture() {
        videoURL = nil
        frames = []
        qualityReport = nil
        errorMessage = nil
        step = .capture
    }

    /// Quality passed: move to scoring.
    func proceedToScoring() {
        guard let exercise = selectedExercise else { return }
        step = .processing
        Task {
            // A beat of perceived work; extraction already happened during the quality check.
            try? await Task.sleep(for: .milliseconds(400))
            let reps = RepAnalyzer.analyze(frames: frames)
            let weights = TechniqueScorer.Weights.from(ContentRepository.shared.numbers("scoring", "weights"))
            let thresholds = TechniqueScorer.Thresholds.from(ContentRepository.shared.numbers("scoring", "thresholds"))
            result = TechniqueScorer.score(exerciseId: exercise.id, reps: reps, weights: weights, thresholds: thresholds)
            step = .result
        }
    }

    func startOver() {
        step = .exercise
        selectedExercise = nil
        videoURL = nil
        frames = []
        qualityReport = nil
        result = nil
        errorMessage = nil
    }

    private func runQualityCheck() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        guard let url = videoURL else { return }
        do {
            // Detached: extraction walks the whole clip synchronously frame by frame and would
            // otherwise tie up the cooperative thread pool for the clip's full duration.
            let extracted = try await Task.detached {
                try await VisionPoseExtractor.extract(from: url)
            }.value
            frames = extracted
            let thresholds = QualityGate.Thresholds.from(ContentRepository.shared.numbers("scoring", "quality"))
            qualityReport = QualityGate.assess(frames: extracted, thresholds: thresholds)
        } catch {
            frames = []
            qualityReport = nil
            errorMessage = "Nie udało się odczytać nagrania. Spróbuj ponownie."
        }
    }
}
