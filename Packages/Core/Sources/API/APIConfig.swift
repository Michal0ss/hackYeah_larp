import Foundation

/// Where the backend is and who we are. The model key is NOT here: it lives only on the server.
public struct APIConfig: Sendable, Equatable {
    public var baseURL: URL?
    /// App token (one of the server's FORMA_APP_TOKENS). Empty while the server runs without tokens.
    public var token: String
    /// Random id created once per install; the server rate-limits per device.
    public var deviceId: String

    public init(baseURL: URL?, token: String = "", deviceId: String = APIConfig.storedDeviceId()) {
        self.baseURL = baseURL
        self.token = token
        self.deviceId = deviceId
    }

    /// Reads FormaAPIURL and FormaAPIToken from Info.plist (filled from Config/*.xcconfig).
    public static func fromBundle(_ bundle: Bundle = .main) -> APIConfig {
        let url = (bundle.object(forInfoDictionaryKey: "FormaAPIURL") as? String).flatMap(URL.init(string:))
        let token = bundle.object(forInfoDictionaryKey: "FormaAPIToken") as? String ?? ""
        return APIConfig(baseURL: url, token: token)
    }

    public static func storedDeviceId(defaults: UserDefaults = .standard) -> String {
        let key = "forma.deviceId"
        if let existing = defaults.string(forKey: key) { return existing }
        let created = UUID().uuidString
        defaults.set(created, forKey: key)
        return created
    }
}
