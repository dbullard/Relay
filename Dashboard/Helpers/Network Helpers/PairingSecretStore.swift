import Foundation
import Security

public protocol PairingSecretStoring: AnyObject {
    func secret(for deviceId: String) -> Data?
    func setSecret(_ secret: Data?, for deviceId: String)
}

final class InMemoryPairingSecretStore: PairingSecretStoring {
    private var storage: [String: Data] = [:]
    func secret(for deviceId: String) -> Data? { storage[deviceId] }
    func setSecret(_ secret: Data?, for deviceId: String) { storage[deviceId] = secret }
}

/// Keychain-backed; mirrors the style of `LicenseKeychainStore`.
public final class KeychainPairingSecretStore: PairingSecretStoring {
    private let service = "com.relay.lan.pairing"

    public init() {}

    public func secret(for deviceId: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    public func setSecret(_ secret: Data?, for deviceId: String) {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceId
        ]
        SecItemDelete(match as CFDictionary)
        guard let secret else { return }
        var add = match
        add[kSecValueData as String] = secret
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
