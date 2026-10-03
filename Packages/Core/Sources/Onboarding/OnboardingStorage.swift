import Foundation
import Contracts

public protocol OnboardingStoring: Sendable {
    func load() -> OnboardingResult?
    func save(_ result: OnboardingResult) throws
    /// Removes the health history and keeps the profile and the plan.
    func deleteHealthHistory() throws
    /// Removes everything (used to run onboarding again).
    func clear() throws
}

/// Profile and plan are not sensitive. The health history lives in its own file that is
/// protected while the phone is locked and excluded from backups, so it never leaves the device.
public struct FileOnboardingStorage: OnboardingStoring {
    private struct ProfileFile: Codable {
        var profile: UserProfile
        var plan: TrainingPlan
        var healthAccess: HealthAccessChoice
        var completedAt: Date
    }

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static var `default`: FileOnboardingStorage {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return FileOnboardingStorage(directory: base.appendingPathComponent("Forma/Onboarding", isDirectory: true))
    }

    private var profileURL: URL { directory.appendingPathComponent("profile.json") }
    private var healthURL: URL { directory.appendingPathComponent("health-history.json") }

    public func load() -> OnboardingResult? {
        let decoder = JSONDecoder()
        guard let data = try? Data(contentsOf: profileURL),
              let file = try? decoder.decode(ProfileFile.self, from: data) else { return nil }
        let health = (try? Data(contentsOf: healthURL)).flatMap { try? decoder.decode(HealthHistory.self, from: $0) }
        return OnboardingResult(profile: file.profile, health: health ?? HealthHistory(), plan: file.plan,
                                healthAccess: file.healthAccess, completedAt: file.completedAt)
    }

    public func save(_ result: OnboardingResult) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Default date coding keeps full precision, so a saved plan loads back identical.
        let encoder = JSONEncoder()

        let file = ProfileFile(profile: result.profile, plan: result.plan, healthAccess: result.healthAccess,
                               completedAt: result.completedAt)
        try encoder.encode(file).write(to: profileURL, options: .atomic)

        var options: Data.WritingOptions = .atomic
        #if os(iOS)
        options.insert(.completeFileProtection)
        #endif
        try encoder.encode(result.health).write(to: healthURL, options: options)

        var url = healthURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    public func deleteHealthHistory() throws {
        if FileManager.default.fileExists(atPath: healthURL.path) {
            try FileManager.default.removeItem(at: healthURL)
        }
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}

/// For previews and tests: nothing touches the disk.
public final class InMemoryOnboardingStorage: OnboardingStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: OnboardingResult?

    public init(_ initial: OnboardingResult? = nil) {
        self.stored = initial
    }

    public func load() -> OnboardingResult? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func save(_ result: OnboardingResult) throws {
        lock.lock(); defer { lock.unlock() }
        stored = result
    }

    public func deleteHealthHistory() throws {
        lock.lock(); defer { lock.unlock() }
        stored?.health = HealthHistory()
    }

    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}
