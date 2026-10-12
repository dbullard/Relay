import Foundation
import Security

final class ProPresenterKeychainStore {
    static let shared = ProPresenterKeychainStore()
    private let service = "com.relay.propresenter"
    private let passwordKey = "password"

    private init() {}

    var password: String {
        get { loadString(forKey: passwordKey) ?? "" }
        set {
            if newValue.isEmpty {
                clear(forKey: passwordKey)
            } else {
                saveString(newValue, forKey: passwordKey)
            }
        }
    }

    /// One-time migration: reads from UserDefaults, writes to Keychain, clears UserDefaults.
    func migrateFromUserDefaultsIfNeeded() {
        let defaults = UserDefaults.standard
        let legacyKey = "propresenter_password"
        guard let legacy = defaults.string(forKey: legacyKey), !legacy.isEmpty else { return }
        if loadString(forKey: passwordKey) == nil {
            saveString(legacy, forKey: passwordKey)
        }
        defaults.removeObject(forKey: legacyKey)
    }

    private func loadString(forKey key: String) -> String? {
        guard let data = loadData(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveString(_ value: String, forKey key: String) {
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

    private func saveData(_ data: Data, forKey key: String) {
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let updateStatus = SecItemUpdate(attrs as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var addQuery = attrs
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            _ = SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func clear(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
