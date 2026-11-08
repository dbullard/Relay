import Foundation
import Security

/// Credentials people supply for services Relay can't ship keys for (Planning Center,
/// YouTube). Values entered in Settings > Integrations take priority over build-time
/// values from Info.plist / `Config/Local.xcconfig`. OAuth client IDs are not secret and live
/// in UserDefaults; the YouTube client secret is kept in the Keychain.
enum ServiceCredentials {
    enum Key {
        static let pcoClientID = "relay_pco_oauth_client_id"
        static let youTubeClientID = "relay_youtube_oauth_client_id"
        static let youTubeRedirectURI = "relay_youtube_oauth_redirect_uri"
    }

    private static let secretService = "app.relay.youtube.oauth.client"
    private static let secretAccount = "client_secret"

    static func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The user-entered value if there is one, otherwise the Info.plist value(s), otherwise "".
    static func resolved(defaultsKey: String, plistKeys: [String], defaults: UserDefaults = .standard, bundle: Bundle = .main) -> String {
        let entered = trimmed(defaults.string(forKey: defaultsKey))
        if !entered.isEmpty { return entered }
        for key in plistKeys {
            let value = trimmed(bundle.object(forInfoDictionaryKey: key) as? String)
            if !value.isEmpty { return value }
        }
        return ""
    }

    static func set(_ value: String, forKey key: String, defaults: UserDefaults = .standard) {
        let value = trimmed(value)
        if value.isEmpty { defaults.removeObject(forKey: key) } else { defaults.set(value, forKey: key) }
    }

    // MARK: YouTube client secret (Keychain)

    static func youTubeClientSecret() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secretService,
            kSecAttrAccount as String: secretAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else { return nil }
        let value = trimmed(text)
        return value.isEmpty ? nil : value
    }

    static func setYouTubeClientSecret(_ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: secretService,
            kSecAttrAccount as String: secretAccount
        ]
        SecItemDelete(base as CFDictionary)
        let secret = trimmed(value)
        guard !secret.isEmpty, let data = secret.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
