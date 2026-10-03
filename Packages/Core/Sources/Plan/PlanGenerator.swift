import API
import Contracts
import Foundation

/// The backend, as far as the plan generator needs it. `FormaAPI` is the real one; tests use a fake.
public protocol PlanBackend: Sendable {
    func generatePlan(for profile: UserProfile) async throws -> PlanGenerateResponse
}

extension FormaAPI: PlanBackend {}

/// Builds the user's plan: a week from the model or the template, laid out on the calendar for several weeks.
/// The week: the model through the backend when it can, the bundled template when it cannot.
///
///     profile ──► backend (model proposes, server validates, server template as its own fallback)
///                    │ plan                                   │ no answer in time, no connection, server error
///                    ▼                                        ▼
///            validated again here ── ok ──► plan            plan built here from the bundled template
///                    │ not ok ──────────────────────────────►(with a notice saying why)
///
/// It never leaves the user without a plan: every failure ends in a plan built on the phone, with a `PlanNotice` that
/// the screens show. It throws only when the task is cancelled.
public struct PlanGenerator: PlanGenerating {
    private let backend: PlanBackend
    private let catalog: ExerciseCatalogProviding
    private let templates: PlanTemplates?
    private let deadline: TimeInterval
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - catalog: read at the moment of generating, so a catalog refreshed from the backend is used.
    ///   - deadline: how long to wait for the backend before building the plan here. The server itself gives the
    ///     model 50 s, so the default leaves room for the network.
    public init(backend: PlanBackend, catalog: ExerciseCatalogProviding, templates: PlanTemplates? = PlanTemplates.bundled(),
                deadline: TimeInterval = 60, now: @escaping @Sendable () -> Date = { Date() }) {
        self.backend = backend
        self.catalog = catalog
        self.templates = templates
        self.deadline = deadline
        self.now = now
    }

    /// The plan with dates: the weekly pattern (from the model or the template) laid out from today for
    /// `PlanScheduler.defaultWeeks` weeks.
    public func generatePlan(for profile: UserProfile) async throws -> TrainingPlan {
        let pattern = try await generatePattern(for: profile)
        return PlanScheduler.schedule(pattern, startingOn: now())
    }

    /// The weekly pattern, checked, before it is laid out on the calendar.
    func generatePattern(for profile: UserProfile) async throws -> TrainingPlan {
        do {
            let response = try await fetch(profile)
            let issues = PlanValidator.validate(response.plan, profile: profile, catalog: catalog.exercises, templates: templates)
            guard issues.isEmpty else { return await localPlan(for: profile, because: .aiInvalidPlan) }
            var plan = response.plan
            plan.notices = Self.notices(from: response.warnings)
            return plan
        } catch {
            // A cancelled task must not quietly turn into a plan nobody asked for.
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            return await localPlan(for: profile, because: Self.notice(for: error))
        }
    }

    // MARK: backend

    private struct DeadlineExceeded: Error {}

    private func fetch(_ profile: UserProfile) async throws -> PlanGenerateResponse {
        try await withThrowingTaskGroup(of: PlanGenerateResponse?.self) { group in
            group.addTask { try await backend.generatePlan(for: profile) }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(deadline * 1_000_000_000))
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw DeadlineExceeded() }
            guard let response = first else { throw DeadlineExceeded() }
            return response
        }
    }

    static func notice(for error: Error) -> PlanNotice {
        switch error as? APIError {
        case .transport?, .notConfigured?: return .offline
        default: return .aiUnavailable  // server error, bad answer or no answer in time
        }
    }

    /// Server warnings (backend/README.md) as notices. `ai_mock` is the dev server without a key: nothing to tell the user.
    static func notices(from warnings: [String]) -> [PlanNotice] {
        var result: [PlanNotice] = []
        for warning in warnings {
            let notice: PlanNotice?
            switch warning {
            case "ai_unavailable": notice = .aiUnavailable
            case "ai_invalid_plan": notice = .aiInvalidPlan
            case "avoid_text_not_applied": notice = .avoidTextNotApplied
            default: notice = nil
            }
            if let notice, !result.contains(notice) { result.append(notice) }
        }
        return result
    }

    // MARK: local plan

    /// The plan built on the phone. If even that fails (templates missing or the catalog too small), the sample
    /// plan from `SampleServices` still honours days, equipment-free exercises and avoided movements as far as it can.
    private func localPlan(for profile: UserProfile, because reason: PlanNotice) async -> TrainingPlan {
        var notices = [reason]
        if !profile.avoid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { notices.append(.avoidTextNotApplied) }
        let items = catalog.exercises
        if let templates,
           var plan = TemplatePlanBuilder(templates: templates, catalog: items).build(for: profile, now: now()),
           PlanValidator.validate(plan, profile: profile, catalog: items, templates: templates).isEmpty {
            plan.notices = notices
            return plan
        }
        var plan = (try? await SampleServices().generatePlan(for: profile))
            ?? TrainingPlan(createdAt: now(), source: .template, sessions: SampleData.plan.sessions)
        plan.notices = notices
        return plan
    }
}
