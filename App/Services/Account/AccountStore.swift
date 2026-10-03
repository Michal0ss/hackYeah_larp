import Foundation
import Observation

/// Who is signed in, and whether the person has made the choice at the first launch. Optional on purpose: the app
/// works fully without an account, an account only lets the plan and the answers follow the person to another phone.
@MainActor
@Observable
final class AccountStore {
    enum Phase: Equatable {
        /// First launch, nothing chosen yet: the sign-in screen shows before onboarding.
        case undecided
        /// "Continue without an account".
        case skipped
        case signedIn
    }

    /// What the person agreed to when creating the account. Bumped whenever the text they agree to changes.
    static let policyVersion = "2026-10-04-draft"

    private(set) var phase: Phase
    private(set) var user: AccountUser?
    /// A sign-in is in progress. Separate from `phase` so the sign-in screen stays up while Google is open.
    private(set) var isSigningIn = false
    /// Shown under the button when sign-in failed. nil after a cancel (not an error).
    private(set) var errorMessage: String?

    @ObservationIgnored private let sessions: AccountSessionStoring
    @ObservationIgnored private let client: SupabaseAuthClient
    @ObservationIgnored private let defaults: UserDefaults
    private static let skippedKey = "accountSkipped"

    init(sessions: AccountSessionStoring = KeychainSessionStore(),
         client: SupabaseAuthClient = SupabaseAuthClient(config: .current),
         defaults: UserDefaults = .standard) {
        self.sessions = sessions
        self.client = client
        self.defaults = defaults
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-reset-account") {
            sessions.clear()
            defaults.removeObject(forKey: Self.skippedKey)
        }
        if arguments.contains("-reset-onboarding") { defaults.removeObject(forKey: Self.skippedKey) }
        if arguments.contains("-skip-onboarding") || arguments.contains("-skip-login") {
            defaults.set(true, forKey: Self.skippedKey)
        }
        #endif
        if let saved = sessions.load() {
            user = saved.user
            phase = .signedIn
        } else {
            phase = defaults.bool(forKey: Self.skippedKey) ? .skipped : .undecided
        }
    }

    var isSignedIn: Bool { phase == .signedIn }
    var needsChoice: Bool { phase == .undecided }

    /// "Continue without an account".
    func skip() {
        defaults.set(true, forKey: Self.skippedKey)
        errorMessage = nil
        phase = .skipped
    }

    /// Opens Google through `authenticate` (a web sign-in session that returns the redirect address) and trades the
    /// returned code for a session. `acceptedAt` is when the person ticked the consent.
    func signInWithGoogle(acceptedAt: Date, authenticate: (URL) async throws -> URL) async {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        errorMessage = nil
        let verifier = PKCE.makeVerifier()
        do {
            let callback = try await authenticate(client.authorizeURL(challenge: PKCE.challenge(for: verifier)))
            let code = try SupabaseAuthClient.code(from: callback)
            let session = try await client.exchange(code: code, verifier: verifier)
            sessions.save(session)
            user = session.user
            defaults.removeObject(forKey: Self.skippedKey)
            phase = .signedIn
            // The name and the consent go to the profile row. The sign-in itself already worked, so a failure here
            // (for example the table is not there yet) is not shown as a failed sign-in.
            try? await client.upsertProfile(session: session, consentAt: acceptedAt, policyVersion: Self.policyVersion)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Reads the saved session at launch and refreshes it when it has expired. A refresh the service refuses means
    /// the session is over: the person is signed out on this phone.
    func restore() async {
        guard var session = sessions.load() else { return }
        if session.needsRefresh() {
            do {
                session = try await client.refresh(session)
                sessions.save(session)
            } catch SupabaseAuthClient.AuthError.server {
                await signOut()
                return
            } catch {
                // No connection: keep the saved session and try again next time.
            }
        }
        user = session.user
        phase = .signedIn
    }

    func signOut() async {
        if let session = sessions.load() { await client.signOut(accessToken: session.accessToken) }
        sessions.clear()
        user = nil
        errorMessage = nil
        phase = .skipped
    }

    static func message(for error: Error) -> String? {
        if (error as NSError).domain == "com.apple.AuthenticationServices.WebAuthenticationSession",
           (error as NSError).code == 1 {
            return nil  // the person closed the sign-in window
        }
        if case SupabaseAuthClient.AuthError.noCode(let reason) = error, reason == nil { return nil }
        if error is URLError { return "Brak połączenia. Sprawdź internet i spróbuj ponownie." }
        return "Nie udało się zalogować. Spróbuj ponownie za chwilę."
    }
}
