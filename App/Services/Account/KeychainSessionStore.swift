import Foundation
import Security

protocol AccountSessionStoring {
    func load() -> AccountSession?
    func save(_ session: AccountSession)
    func clear()
}

/// The session (tokens) lives in the Keychain, not in a plain file: it is a key to the person's account. Readable only
/// after the first unlock and never copied to another device or a backup.
struct KeychainSessionStore: AccountSessionStoring {
    private let service = "pl.forma.account"
    private let account = "session"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    func load() -> AccountSession? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(AccountSession.self, from: data)
    }

    func save(_ session: AccountSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let update = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func clear() {
        SecItemDelete(query as CFDictionary)
    }
}

/// In memory only (previews and tests).
final class MemorySessionStore: AccountSessionStoring, @unchecked Sendable {
    private var session: AccountSession?
    func load() -> AccountSession? { session }
    func save(_ session: AccountSession) { self.session = session }
    func clear() { session = nil }
}
