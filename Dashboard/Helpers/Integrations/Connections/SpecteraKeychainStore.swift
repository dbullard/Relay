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
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
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
            SecItemDelete(baseQuery as CFDictionary)
            return
        }
        let data = Data(password.utf8)
        if SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary) != errSecSuccess {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
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
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func setTrustedCertificate(_ certificate: Data, for deviceID: UUID) {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: certificateService,
            kSecAttrAccount as String: deviceID.uuidString
        ]
        if SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: certificate] as CFDictionary) != errSecSuccess {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = certificate
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}
