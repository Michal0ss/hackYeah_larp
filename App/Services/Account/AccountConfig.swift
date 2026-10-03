import Foundation

/// Where the account service lives (Supabase Auth and database). Both values are public by design: the publishable
/// key only says which project to talk to, and what a signed-in person may read or change is decided on the server by
/// row-level security. The key to the language model and the backend token are different things and never go here.
struct AccountConfig: Sendable {
    let url: URL
    let publishableKey: String
    /// The app receives the sign-in result on `<scheme>://auth-callback`. The same address must be on the redirect
    /// allow-list of the Supabase project (Authentication, URL Configuration).
    let callbackScheme: String

    var callbackURL: URL { URL(string: "\(callbackScheme)://auth-callback")! }

    static let current = AccountConfig(
        url: URL(string: "https://vugyfupgtgiyraeihhkg.supabase.co")!,
        publishableKey: "sb_publishable_AeXMaEdNeQCpZjK0nczJpA_746gKVL7",
        callbackScheme: "forma")
}
