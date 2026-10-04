import Foundation
import Observation
import Contracts
import LiveSet
import Onboarding

/// The two answers about mobility (legs and hips, shoulders), kept on the phone only: never synced to the account and
/// never sent to the backend. `current()` puts them together with the level and the injuries from onboarding into the
/// `TechniqueContext` the assessment uses, so a set and a recorded clip are judged with the same context.
@MainActor
@Observable
final class TechniqueContextStore {
    static let shared = TechniqueContextStore()

    private struct Answers: Codable, Equatable {
        var lowerBody: Mobility
        var shoulder: Mobility
    }

    private(set) var lowerBody: Mobility = .typical
    private(set) var shoulder: Mobility = .typical

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let onboarding: OnboardingStoring

    init(fileURL: URL? = TechniqueContextStore.defaultFileURL(), onboarding: OnboardingStoring = FileOnboardingStorage.default) {
        self.fileURL = fileURL
        self.onboarding = onboarding
        if let fileURL, let data = try? Data(contentsOf: fileURL), let answers = try? JSONDecoder().decode(Answers.self, from: data) {
            lowerBody = answers.lowerBody
            shoulder = answers.shoulder
        }
    }

    func setLowerBody(_ value: Mobility) {
        lowerBody = value
        persist()
    }

    func setShoulder(_ value: Mobility) {
        shoulder = value
        persist()
    }

    /// "Usuń wszystkie dane": the answers go with everything else.
    func clear() {
        lowerBody = .typical
        shoulder = .typical
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    /// The answers, the level from onboarding and the injuries from the health history (read from the phone's own
    /// storage, so deleting the health history takes its effect away too).
    func current() -> TechniqueContext {
        let saved = onboarding.load()
        // The mobility answers are not asked anywhere at the moment (the Profile card is gone), so an answer saved
        // earlier does not keep changing the assessment: only the level and the injuries from onboarding count.
        return TechniqueContext(lowerBodyMobility: .typical, shoulderMobility: .typical,
                                level: saved?.profile.level ?? .intermediate,
                                lowerBodyCaution: saved?.health.hasRecentLowerBodyInjury ?? false,
                                upperBodyCaution: saved?.health.hasRecentUpperBodyInjury ?? false)
    }

    private func persist() {
        guard let fileURL, let data = try? JSONEncoder().encode(Answers(lowerBody: lowerBody, shoulder: shoulder)) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        #else
        try? data.write(to: fileURL, options: .atomic)
        #endif
    }

    nonisolated static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Forma/technique-context.json")
    }
}
