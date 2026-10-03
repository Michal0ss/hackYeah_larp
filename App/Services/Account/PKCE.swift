import CryptoKit
import Foundation

/// Proof Key for Code Exchange (RFC 7636): the app invents a secret, sends only its hash when signing in, and shows
/// the secret when trading the returned code for a session. A stolen code is useless without it.
enum PKCE {
    /// 32 random bytes as base64url: 43 characters, inside the 43...128 the RFC allows.
    static func makeVerifier() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255, using: &generator) }
        return base64URL(Data(bytes))
    }

    /// `S256`: base64url of the SHA-256 of the verifier.
    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
