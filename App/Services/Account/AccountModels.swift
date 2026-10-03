import Foundation

struct AccountUser: Codable, Equatable, Sendable {
    var id: String
    var email: String?
    var firstName: String
    var lastName: String

    var displayName: String {
        let name = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? (email ?? "Konto") : name
    }
}

struct AccountSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var user: AccountUser

    /// True when the access token is expired or about to be (`leeway` seconds), so it should be refreshed first.
    func needsRefresh(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        expiresAt <= now.addingTimeInterval(leeway)
    }
}

enum PersonName {
    /// First and last name from what Google gives: separate fields when present, otherwise the full name split at the
    /// first space ("Anna Maria Nowak" gives "Anna" and "Maria Nowak"). Empty strings when nothing is known.
    static func split(given: String?, family: String?, full: String?) -> (first: String, last: String) {
        func clean(_ value: String?) -> String {
            (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let given = clean(given), family = clean(family)
        if !given.isEmpty || !family.isEmpty { return (given, family) }
        let parts = clean(full).split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first else { return ("", "") }
        return (String(first), parts.count > 1 ? String(parts[1]) : "")
    }
}
