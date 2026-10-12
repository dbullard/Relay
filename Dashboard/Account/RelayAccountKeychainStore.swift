import Foundation
import Security

protocol RelayAccountTokenStore: AnyObject {
    var sessionToken: String? { get set }
    @discardableResult
    func saveRelayAccountToken(_ token: String) -> Bool
    func loadRelayAccountToken() -> String?
    @discardableResult
    func deleteRelayAccountToken() -> Bool
}

final class RelayAccountKeychainStore: RelayAccountTokenStore {
    static let shared = RelayAccountKeychainStore()

    private let service = "com.relay.account"
    private let tokenKey = "relay_account_session_token"

    private init() {}

    /// Convenience setter used by test doubles/setup code. Discards
    /// save/delete failures — callers that must react to a failed write
    /// (e.g. RelayAccountCoordinator's sign-in/logout paths) should call
    /// saveRelayAccountToken(_:)/deleteRelayAccountToken() directly instead.
    var sessionToken: String? {
        get { loadRelayAccountToken() }
        set {
            guard let newValue, !newValue.isEmpty else {
                deleteRelayAccountToken()
                return
            }
            saveRelayAccountToken(newValue)
        }
    }

    @discardableResult
    func saveRelayAccountToken(_ token: String) -> Bool {
        saveString(token, forKey: tokenKey)
    }

    func loadRelayAccountToken() -> String? {
        loadString(forKey: tokenKey)
    }

    @discardableResult
    func deleteRelayAccountToken() -> Bool {
        clear(forKey: tokenKey)
    }

    private func loadString(forKey key: String) -> String? {
        guard let data = loadData(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveString(_ value: String, forKey key: String) -> Bool {
        saveData(Data(value.utf8), forKey: key)
    }

    private func loadData(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return data
    }

    private func saveData(_ data: Data, forKey key: String) -> Bool {
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let updateStatus = SecItemUpdate(
            attrs as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess { return true }

        if updateStatus == errSecItemNotFound {
            var addQuery = attrs
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }

        clear(forKey: key)
        var addQuery = attrs
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    private func clear(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
