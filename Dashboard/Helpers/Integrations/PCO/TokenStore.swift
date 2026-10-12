import Foundation
import Security
import LocalAuthentication

public struct OAuthTokens: Codable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
}

public protocol TokenStore: AnyObject {
    func loadTokens() -> OAuthTokens?
    func saveTokens(_ tokens: OAuthTokens?)
    func clear()
}

// A simple Keychain-backed token store for iOS and macOS.
public final class KeychainTokenStore: TokenStore {
    private let service = "com.pcodigicoapp.oauth"
    private let account = "pcoplanningcenter"

    public init() {}

    public func loadTokens() -> OAuthTokens? {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    public func saveTokens(_ tokens: OAuthTokens?) {
        // If nil tokens passed, clear and return
        guard let tokens else {
            clear()
            return
        }

        let data = (try? JSONEncoder().encode(tokens)) ?? Data()

        // Common attributes for the item
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Attempt update first
        let updateStatus = SecItemUpdate(
            attrs as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess {
            return
        }

        // If item not found, add it
        if updateStatus == errSecItemNotFound {
            let addContext = LAContext()
            addContext.interactionNotAllowed = true
            var addQuery = attrs
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            addQuery[kSecUseAuthenticationContext as String] = addContext
            _ = SecItemAdd(addQuery as CFDictionary, nil)
            return
        }

        // Fallback: if update failed for another reason, try clear + add
        clear()
        let addContext = LAContext()
        addContext.interactionNotAllowed = true
        var addQuery = attrs
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        addQuery[kSecUseAuthenticationContext as String] = addContext
        _ = SecItemAdd(addQuery as CFDictionary, nil)
    }

    public func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
