import Foundation
import Security

protocol SmartLightSecretStoreBackend {
    func load(service: String, account: String) -> Data?
    func save(service: String, account: String, data: Data)
    func clear(service: String, account: String)
}

struct SmartLightKeychainBackend: SmartLightSecretStoreBackend {
    func load(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return data
    }

    func save(service: String, account: String, data: Data) {
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateStatus = SecItemUpdate(attrs as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        var addAttrs = attrs
        addAttrs[kSecValueData as String] = data
        addAttrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        _ = SecItemAdd(addAttrs as CFDictionary, nil)
    }

    func clear(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class SmartLightKeychainStore {
    static let shared = SmartLightKeychainStore()

    private let service = "com.relay.smartlights"
    private let backend: SmartLightSecretStoreBackend

    init(backend: SmartLightSecretStoreBackend = SmartLightKeychainBackend()) {
        self.backend = backend
    }

    func loadSecret(profileID: UUID, kind: SmartLightSecretKind) -> String? {
        let account = SmartLightProfileSecretReference.make(profileID: profileID, kind: kind)
        guard let data = backend.load(service: service, account: account) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func saveSecret(_ value: String?, profileID: UUID, kind: SmartLightSecretKind) {
        let account = SmartLightProfileSecretReference.make(profileID: profileID, kind: kind)
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            backend.clear(service: service, account: account)
            return
        }
        backend.save(service: service, account: account, data: Data(value.utf8))
    }

    func clearSecrets(for profileID: UUID) {
        for kind in [SmartLightSecretKind.goveeAPIKey, .hueApplicationKey] {
            let account = SmartLightProfileSecretReference.make(profileID: profileID, kind: kind)
            backend.clear(service: service, account: account)
        }
    }
}

