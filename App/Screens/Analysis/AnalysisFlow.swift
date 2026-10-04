import Analysis
import Content
import Contracts
import CoreGraphics
import Foundation
import LiveSet
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
    /// True when the report has failed checks but the clip shows at least one repetition, so the person may analyse it
    /// anyway (the result is then marked as approximate).
    private(set) var canAnalyzeAnyway = false
    /// The analysed clip, for the chart and the cards of the result.
    private(set) var analysis: RepAnalyzer.Analysis?
    /// The result was computed although some checks of the quality gate failed.
    private(set) var analysedDespiteWarnings = false
    private(set) var result: TechniqueResult?
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    /// While the clip is read: how far, and the pose (with a small still of the picture) of the frame just done, so the
    /// screen can show the skeleton being caught like in the live set. Kept in memory only.
    private(set) var extractionFraction = 0.0
    private(set) var previewFrame: PoseFrame?
    private(set) var previewImage: CGImage?
    private(set) var framesAnalysed = 0
    private var extractionTask: Task<Void, Never>?

    /// Ranges of joint angles and the rep detector's limits, from `content/config/scoring.json`. Read once when a clip
    /// is picked, not on every screen redraw.
    private(set) var angleReference = AngleReference()
    private var clipConfig = ClipRepDetector.Config()

    /// What the result screen draws, worked out once when the clip is scored instead of on every redraw: the smoothed
    /// angle over time and the angle at the working end of every repetition (by repetition number).
    private(set) var angleSeries: [(time: Double, angle: Double)] = []
    private(set) var repAngles: [Int: Double] = [:]

    private func loadConfig() {
        angleReference = AngleReference(values: ContentRepository.shared.numbers("scoring", "angles"))
        clipConfig = ClipRepDetector.Config(values: ContentRepository.shared.numbers("scoring", "clip"))
    }

    /// Which live-set movement this exercise maps to; defaults to squat (shouldn't happen since
    /// the exercise picker only lists catalog items `MovementKind.kind(for:)` can resolve).
    var kind: MovementKind {
        selectedExercise.flatMap(MovementKind.kind(for:)) ?? .squat
    }

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

    /// A video was recorded or picked from the gallery; read it (showing the skeleton as it is found) and run the
    /// quality gate on it.
    func use(video url: URL) {
        videoURL = url
        step = .quality
        loadConfig()
        extractionTask?.cancel()
        extractionTask = Task { await runQualityCheck() }
    }

    func retryCapture() {
        extractionTask?.cancel()
        extractionTask = nil
        deleteVideoFileIfNeeded()
        resetClip()
        step = .capture
    }

    /// Quality passed, or the person chose to analyse the clip anyway: move to scoring.
    func proceedToScoring(anyway: Bool = false) {
        guard let exercise = selectedExercise else { return }
        step = .processing
        analysedDespiteWarnings = anyway && !(qualityReport?.passed ?? true)
        Task {
            let weights = TechniqueScorer.Weights.from(ContentRepository.shared.numbers("scoring", "weights"))
            let thresholds = TechniqueScorer.Thresholds.from(ContentRepository.shared.numbers("scoring", "thresholds"))
            let reference = angleReference, clip = clipConfig
            let analysis = RepAnalyzer.analyze(frames: frames, kind: kind, config: clip, depthTolerance: reference.squatDepthTolerance)
            self.analysis = analysis
            angleSeries = RepAnalyzer.angleSeries(in: frames, kind: kind)
            repAngles = Dictionary(uniqueKeysWithValues: analysis.clipReps.compactMap { rep in
                kind.primaryAngle(in: rep.bottomFrame, minConfidence: 0.15).map { (rep.index, $0) }
            })
            result = TechniqueScorer.score(exerciseId: exercise.id, kind: kind, frames: frames,
                                           weights: weights, thresholds: thresholds, reference: reference, clip: clip)
            step = .result
        }
    }

    func startOver() {
        extractionTask?.cancel()
        extractionTask = nil
        deleteVideoFileIfNeeded()
        step = .exercise
        selectedExercise = nil
        resetClip()
        result = nil
    }

    private func resetClip() {
        frames = []
        qualityReport = nil
        canAnalyzeAnyway = false
        analysis = nil
        angleSeries = []
        repAngles = [:]
        analysedDespiteWarnings = false
        errorMessage = nil
        extractionFraction = 0
        previewFrame = nil
        previewImage = nil
        framesAnalysed = 0
    }

    private func apply(_ progress: ClipExtractionProgress) {
        extractionFraction = progress.fraction
        previewFrame = progress.frame
        if let image = progress.image { previewImage = image }
        framesAnalysed = progress.framesDone
    }

    /// We promise videos never stay on the phone: delete it the moment we're done reading it,
    /// on every path (quality pass, quality fail, retry, start over).
    private func deleteVideoFileIfNeeded() {
        if let url = videoURL {
            try? FileManager.default.removeItem(at: url)
        }
        videoURL = nil
    }

    private func runQualityCheck() async {
        resetClip()
        isWorking = true
        defer { isWorking = false }
        guard let url = videoURL else { return }
        do {
            // Detached: extraction walks the whole clip synchronously frame by frame and would
            // otherwise tie up the cooperative thread pool for the clip's full duration.
            let worker = Task.detached { [weak self] in
                try await VisionPoseExtractor.extract(from: url) { progress in
                    Task { @MainActor in self?.apply(progress) }
                }
            }
            // A detached task does not inherit cancellation: going back must stop the reading itself.
            let extracted = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
            frames = extracted
            let thresholds = QualityGate.Thresholds.from(ContentRepository.shared.numbers("scoring", "quality"))
            let evaluation = QualityGate.evaluate(frames: extracted, kind: kind, thresholds: thresholds, clip: clipConfig)
            qualityReport = evaluation.report
            canAnalyzeAnyway = evaluation.canAnalyzeAnyway
        } catch is CancellationError {
            // The person went back; nothing to show.
        } catch {
            frames = []
            qualityReport = nil
            errorMessage = "Nie udało się odczytać nagrania. Spróbuj ponownie."
        }
        previewImage = nil
        deleteVideoFileIfNeeded()
    }
}
