import Foundation
import Security

final class SpecteraKeychainStore {
    static let shared = SpecteraKeychainStore()

    private let service = "app.relay.spectera"
    private let certificateService = "app.relay.spectera.certificate"

    func password(for deviceID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard Keychain.copyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func setPassword(_ password: String, for deviceID: UUID) {
        let account = deviceID.uuidString
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        guard !password.isEmpty else {
            Keychain.delete(baseQuery as CFDictionary)
            return
        }
        let data = Data(password.utf8)
        if Keychain.update(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary) != errSecSuccess {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            Keychain.add(addQuery as CFDictionary, nil)
        }
    }

    func trustedCertificate(for deviceID: UUID) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: certificateService,
            kSecAttrAccount as String: deviceID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard Keychain.copyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func setTrustedCertificate(_ certificate: Data, for deviceID: UUID) {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: certificateService,
            kSecAttrAccount as String: deviceID.uuidString
        ]
        if Keychain.update(baseQuery as CFDictionary, [kSecValueData as String: certificate] as CFDictionary) != errSecSuccess {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = certificate
            Keychain.add(addQuery as CFDictionary, nil)
        }
    }
}
