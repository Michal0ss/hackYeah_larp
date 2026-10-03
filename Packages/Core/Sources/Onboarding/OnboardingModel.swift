import Foundation
import Observation
import Contracts

public struct GenerationStage: Equatable, Sendable, Identifiable {
    public enum State: Equatable, Sendable { case done, current, upcoming }

    public var id: Int
    public var label: String
    public var detail: String?
    public var state: State
}

/// State and navigation of the first-run flow. The views only render it.
@MainActor
@Observable
public final class OnboardingModel {
    public enum Generation: Equatable {
        case idle, running, done
        case failed(String)
    }

    public var draft: OnboardingDraft
    public private(set) var step: OnboardingStep = .goal
    public private(set) var healthAccess: HealthAccessChoice?
    public private(set) var isRequestingHealthAccess = false
    public private(set) var healthAccessNotice: String?
    public private(set) var generation: Generation = .idle
    /// 0...1, drives the ring and the stage list on the last step.
    public private(set) var progress = 0.0
    public private(set) var plan: TrainingPlan?

    private let health: HealthAuthorizing
    private let generator: PlanGenerating
    private let minimumGenerationSeconds: Double
    private let tickMilliseconds: Int
    private var pendingOutcome: Result<TrainingPlan, Error>?

    /// - Parameters:
    ///   - minimumGenerationSeconds: how long the generation screen runs at least, so the stages stay readable
    ///     even when the plan is built instantly. Use 0 in tests.
    public init(draft: OnboardingDraft = OnboardingDraft(), health: HealthAuthorizing, generator: PlanGenerating,
                minimumGenerationSeconds: Double = 3.0, tickMilliseconds: Int = 60) {
        self.draft = draft
        self.health = health
        self.generator = generator
        self.minimumGenerationSeconds = minimumGenerationSeconds
        self.tickMilliseconds = max(1, tickMilliseconds)
    }

    // MARK: - Navigation

    public var canGoBack: Bool { step != .goal && step != .generating }

    /// The screening needs an answer to every question, unless a "yes" already calls for caution.
    public var canAdvance: Bool {
        switch step {
        case .screening: return draft.health.result != .incomplete
        case .appleHealth, .generating: return false
        default: return true
        }
    }

    public var screeningResult: ScreeningResult { draft.health.result }

    public func advance() {
        guard canAdvance, let next = step.next else { return }
        step = next
    }

    public func back() {
        guard canGoBack, let previous = step.previous else { return }
        step = previous
    }

    /// "Wolę nie podawać" and "Odpowiem później".
    public func skip() {
        switch step {
        case .medicalHistory:
            draft.health.injuries = []
            draft.health.conditions = []
            draft.health.noConditions = false
        case .screening:
            break
        default:
            return
        }
        if let next = step.next { step = next }
    }

    // MARK: - Apple Health

    public func requestHealthAccess() async {
        guard step == .appleHealth, !isRequestingHealthAccess else { return }
        isRequestingHealthAccess = true
        healthAccessNotice = nil
        let granted = await health.requestAccess()
        isRequestingHealthAccess = false
        if granted {
            healthAccess = .granted
            step = .generating
        } else {
            healthAccessNotice = "Nie udało się uzyskać dostępu do Apple Health. Możesz użyć danych przykładowych albo zmienić zgodę w Ustawieniach."
        }
    }

    public func useSampleHealthData() {
        guard step == .appleHealth else { return }
        healthAccess = .sampleData
        healthAccessNotice = nil
        step = .generating
    }

    // MARK: - Plan generation

    public func startGeneration() async {
        guard step == .generating, generation != .running, generation != .done else { return }
        generation = .running
        progress = 0
        plan = nil
        pendingOutcome = nil

        let profile = draft.makeProfile()
        let generator = self.generator
        let work = Task { () -> Result<TrainingPlan, Error> in
            do { return .success(try await generator.generatePlan(for: profile)) } catch { return .failure(error) }
        }
        Task { [weak self] in
            let outcome = await work.value
            self?.pendingOutcome = outcome
        }

        // Animate towards 90% for at least the minimum time, then wait for the plan.
        let totalTicks = max(1, Int(minimumGenerationSeconds * 1000) / tickMilliseconds)
        var tick = 0
        while !Task.isCancelled {
            if tick < totalTicks {
                tick += 1
                progress = max(progress, 0.9 * Double(tick) / Double(totalTicks))
            } else if pendingOutcome != nil {
                break
            } else {
                progress = min(0.97, progress + 0.002)
            }
            try? await Task.sleep(for: .milliseconds(tickMilliseconds))
        }
        guard !Task.isCancelled else {
            work.cancel()
            generation = .idle
            return
        }

        switch pendingOutcome {
        case .success(let built):
            for i in 1...6 {
                progress = progress + (1 - progress) * Double(i) / 6
                try? await Task.sleep(for: .milliseconds(tickMilliseconds))
            }
            progress = 1
            plan = built
            generation = .done
        case .failure, .none:
            generation = .failed("Nie udało się ułożyć planu. Sprawdź połączenie i spróbuj ponownie.")
        }
    }

    public func retryGeneration() async {
        guard case .failed = generation else { return }
        generation = .idle
        await startGeneration()
    }

    /// Stops a running generation (the screen went away).
    public func cancelGeneration() {
        if generation == .running { generation = .idle }
    }

    // MARK: - Generation screen content

    public var generationStages: [GenerationStage] {
        Self.stages(progress: progress, omit: draft.health.omitTags, easyStart: draft.makeProfile().easyStart)
    }

    /// The four stages shown under the progress ring. Pure, so it is easy to test.
    public static func stages(progress: Double, omit: [MovementTag], easyStart: Bool) -> [GenerationStage] {
        var detail: String?
        if !omit.isEmpty {
            detail = "Pomijam: " + omit.map(\.displayName).joined(separator: ", ")
        }
        if easyStart { detail = (detail.map { $0 + ". " } ?? "") + "Lżejszy start." }

        let defs: [(label: String, at: Double, detail: String?)] = [
            ("Dobieram ćwiczenia z katalogu", 30, nil),
            ("Sprawdzam sprzęt i ograniczenia", 60, detail),
            ("Weryfikuję plan", 90, nil),
            ("Zapisuję tydzień na telefonie", 100, nil),
        ]
        let percent = progress * 100
        return defs.enumerated().map { index, def in
            let previous = index == 0 ? 0 : defs[index - 1].at
            let state: GenerationStage.State = percent >= def.at ? .done : (percent >= previous ? .current : .upcoming)
            return GenerationStage(id: index, label: def.label, detail: def.detail, state: state)
        }
    }

    public var generationSummary: String {
        guard generation == .done, let plan else {
            return "Dobieram ćwiczenia z katalogu do celu, poziomu i sprzętu."
        }
        var text = "Tydzień z \(plan.sessions.count) sesjami po \(draft.sessionMinutes) min, dopasowany do celu i sprzętu."
        let omit = draft.health.omitTags
        if !omit.isEmpty { text += " Bez: " + omit.map(\.displayName).joined(separator: ", ") + "." }
        return text
    }

    // MARK: - Finish

    /// The result to store once the plan is ready and the user taps "Przejdź do Dziś".
    public func makeResult() -> OnboardingResult? {
        guard generation == .done, let plan, let healthAccess else { return nil }
        return OnboardingResult(profile: draft.makeProfile(), health: draft.health, plan: plan, healthAccess: healthAccess)
    }
}
