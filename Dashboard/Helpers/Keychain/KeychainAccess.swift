import Foundation
import Security
import os

/// The one place Relay talks to the keychain. Every store calls `Keychain.copyMatching/add/update/delete`
/// with the same query dictionaries it would pass to `SecItem…`, never the `SecItem…` functions directly.
///
/// Why: locally built test copies (`xcodebuild … CODE_SIGNING_ALLOWED=NO`) are ad-hoc signed and share
/// the bundle id `app.relay.Relay`, so they find the installed app's keychain items. The login keychain
/// trusts an ad-hoc app by its cdhash, which changes on every rebuild, so macOS asks for the keychain
/// password once per item per rebuild and "Always Allow" never sticks. Builds like that get an in-memory
/// stand-in instead: nothing is read from or written to the real keychain, and values saved during the
/// run are gone when it quits. Properly signed builds pass straight through to `SecItem…`, unchanged.
nonisolated enum Keychain {
    static let backend: any KeychainBackend = {
        let signing = CodeSigningSummary.currentProcess()
        let backend = KeychainBackendSelection.backend(for: signing)
        if backend is InMemoryKeychainBackend {
            Logger(subsystem: "Relay", category: "Keychain").notice(
                "Keychain access is disabled because this build is \(signing?.isSigned == false ? "unsigned" : "ad-hoc signed", privacy: .public). Saved credentials and LAN pairing secrets are kept in memory for this run only."
            )
        }
        return backend
    }()

    /// False for unsigned / ad-hoc builds, where keychain items live in memory only.
    static var usesSystemKeychain: Bool { backend is SystemKeychainBackend }

    static func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        backend.copyMatching(query, result)
    }

    @discardableResult
    static func add(_ attributes: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        backend.add(attributes, result)
    }

    @discardableResult
    static func update(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
        backend.update(query, attributesToUpdate)
    }

    @discardableResult
    static func delete(_ query: CFDictionary) -> OSStatus {
        backend.delete(query)
    }
}

// MARK: - Selection

/// What this binary's code signature says, as far as keychain trust is concerned.
nonisolated struct CodeSigningSummary: Equatable, Sendable {
    var isSigned: Bool
    var isAdHoc: Bool
    var teamIdentifier: String?

    /// Reads the running process's signature. Nil when it can't be read (and always on iOS/iPadOS,
    /// where the OS refuses to run unsigned apps on device and the simulator keychain never prompts).
    static func currentProcess() -> CodeSigningSummary? {
        #if os(macOS)
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        let status = SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        if status == errSecCSUnsigned {
            return CodeSigningSummary(isSigned: false, isAdHoc: false, teamIdentifier: nil)
        }
        guard status == errSecSuccess, let dict = info as? [String: Any] else { return nil }
        let flags = (dict[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        return CodeSigningSummary(
            isSigned: true,
            isAdHoc: flags & SecCodeSignatureFlags.adhoc.rawValue != 0,
            teamIdentifier: dict[kSecCodeInfoTeamIdentifier as String] as? String
        )
        #else
        return nil
        #endif
    }
}

nonisolated enum KeychainBackendSelection {
    /// Ad-hoc and unsigned builds have no stable identity for the keychain to trust, so every rebuild
    /// prompts. Anything with a real certificate (Apple Development, Developer ID, App Store) keeps a
    /// stable designated requirement across rebuilds and uses the keychain as before. When the signature
    /// can't be read at all, keep today's behavior.
    static func shouldUseSystemKeychain(_ signing: CodeSigningSummary?) -> Bool {
        guard let signing else { return true }
        return signing.isSigned && !signing.isAdHoc
    }

    static func backend(for signing: CodeSigningSummary?) -> any KeychainBackend {
        shouldUseSystemKeychain(signing) ? SystemKeychainBackend() : InMemoryKeychainBackend()
    }
}

// MARK: - Backends

nonisolated protocol KeychainBackend: Sendable {
    func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func add(_ attributes: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func update(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

nonisolated struct SystemKeychainBackend: KeychainBackend {
    func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        SecItemCopyMatching(query, result)
    }
    func add(_ attributes: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        SecItemAdd(attributes, result)
    }
    func update(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributesToUpdate)
    }
    func delete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}

/// Generic-password items keyed by service + account, enough for the queries Relay's stores make:
/// match one item, return its data, add, update its data, delete. A query without an account matches
/// every account under that service.
nonisolated final class InMemoryKeychainBackend: KeychainBackend, @unchecked Sendable {
    private struct ItemKey: Hashable {
        let service: String
        let account: String
    }

    private let lock = NSLock()
    private var items: [ItemKey: Data] = [:]

    func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        let query = Self.dictionary(query)
        return lock.withLock {
            guard let key = matchingKeys(query).first, let data = items[key] else { return errSecItemNotFound }
            if query[kSecReturnData as String] as? Bool == true {
                result?.pointee = data as CFData
            }
            return errSecSuccess
        }
    }

    func add(_ attributes: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        let attributes = Self.dictionary(attributes)
        guard let service = attributes[kSecAttrService as String] as? String else { return errSecParam }
        let key = ItemKey(service: service, account: attributes[kSecAttrAccount as String] as? String ?? "")
        let data = attributes[kSecValueData as String] as? Data ?? Data()
        return lock.withLock {
            guard items[key] == nil else { return errSecDuplicateItem }
            items[key] = data
            return errSecSuccess
        }
    }

    func update(_ query: CFDictionary, _ attributesToUpdate: CFDictionary) -> OSStatus {
        let query = Self.dictionary(query)
        let changes = Self.dictionary(attributesToUpdate)
        return lock.withLock {
            let keys = matchingKeys(query)
            guard !keys.isEmpty else { return errSecItemNotFound }
            if let data = changes[kSecValueData as String] as? Data {
                for key in keys { items[key] = data }
            }
            return errSecSuccess
        }
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        let query = Self.dictionary(query)
        return lock.withLock {
            let keys = matchingKeys(query)
            guard !keys.isEmpty else { return errSecItemNotFound }
            for key in keys { items[key] = nil }
            return errSecSuccess
        }
    }

    /// Caller holds `lock`.
    private func matchingKeys(_ query: [String: Any]) -> [ItemKey] {
        guard let service = query[kSecAttrService as String] as? String else { return [] }
        if let account = query[kSecAttrAccount as String] as? String {
            let key = ItemKey(service: service, account: account)
            return items[key] == nil ? [] : [key]
        }
        return items.keys.filter { $0.service == service }.sorted { $0.account < $1.account }
    }

    private static func dictionary(_ cf: CFDictionary) -> [String: Any] {
        (cf as NSDictionary) as? [String: Any] ?? [:]
    }
}
