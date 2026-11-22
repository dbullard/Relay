import XCTest
import Security
@testable import Relay

final class KeychainAccessTests: XCTestCase {

    // MARK: Selection

    func testAdHocBuildDoesNotUseSystemKeychain() {
        let adHoc = CodeSigningSummary(isSigned: true, isAdHoc: true, teamIdentifier: nil)
        XCTAssertFalse(KeychainBackendSelection.shouldUseSystemKeychain(adHoc))
        XCTAssertTrue(KeychainBackendSelection.backend(for: adHoc) is InMemoryKeychainBackend)
    }

    func testUnsignedBuildDoesNotUseSystemKeychain() {
        let unsigned = CodeSigningSummary(isSigned: false, isAdHoc: false, teamIdentifier: nil)
        XCTAssertFalse(KeychainBackendSelection.shouldUseSystemKeychain(unsigned))
        XCTAssertTrue(KeychainBackendSelection.backend(for: unsigned) is InMemoryKeychainBackend)
    }

    func testTeamSignedBuildUsesSystemKeychain() {
        let signed = CodeSigningSummary(isSigned: true, isAdHoc: false, teamIdentifier: "ABCDE12345")
        XCTAssertTrue(KeychainBackendSelection.shouldUseSystemKeychain(signed))
        XCTAssertTrue(KeychainBackendSelection.backend(for: signed) is SystemKeychainBackend)
    }

    /// A real certificate without a team id (e.g. Apple platform binaries, a self-signed cert) still has a
    /// stable identity the keychain can trust across rebuilds, so only the ad-hoc flag turns it off.
    func testCertificateSignedBuildWithoutTeamUsesSystemKeychain() {
        let signed = CodeSigningSummary(isSigned: true, isAdHoc: false, teamIdentifier: nil)
        XCTAssertTrue(KeychainBackendSelection.shouldUseSystemKeychain(signed))
    }

    func testUnreadableSignatureKeepsSystemKeychain() {
        XCTAssertTrue(KeychainBackendSelection.shouldUseSystemKeychain(nil))
        XCTAssertTrue(KeychainBackendSelection.backend(for: nil) is SystemKeychainBackend)
    }

    #if os(macOS)
    func testCurrentProcessSummaryMatchesSelectedBackend() throws {
        let summary = try XCTUnwrap(CodeSigningSummary.currentProcess())
        XCTAssertEqual(Keychain.usesSystemKeychain, KeychainBackendSelection.shouldUseSystemKeychain(summary))
    }
    #endif

    // MARK: In-memory backend

    private let service = "app.relay.tests.keychain"

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func read(_ backend: InMemoryKeychainBackend, account: String) -> (OSStatus, Data?) {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = backend.copyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }

    func testInMemoryAddReadUpdateDelete() {
        let backend = InMemoryKeychainBackend()
        XCTAssertEqual(read(backend, account: "a").0, errSecItemNotFound)

        var add = baseQuery(account: "a")
        add[kSecValueData as String] = Data("one".utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        XCTAssertEqual(backend.add(add as CFDictionary, nil), errSecSuccess)
        XCTAssertEqual(backend.add(add as CFDictionary, nil), errSecDuplicateItem)
        XCTAssertEqual(read(backend, account: "a").1, Data("one".utf8))

        let update = [kSecValueData as String: Data("two".utf8)]
        XCTAssertEqual(backend.update(baseQuery(account: "a") as CFDictionary, update as CFDictionary), errSecSuccess)
        XCTAssertEqual(read(backend, account: "a").1, Data("two".utf8))
        XCTAssertEqual(backend.update(baseQuery(account: "b") as CFDictionary, update as CFDictionary), errSecItemNotFound)

        XCTAssertEqual(backend.delete(baseQuery(account: "a") as CFDictionary), errSecSuccess)
        XCTAssertEqual(read(backend, account: "a").0, errSecItemNotFound)
        XCTAssertEqual(backend.delete(baseQuery(account: "a") as CFDictionary), errSecItemNotFound)
    }

    func testInMemoryItemsAreScopedByServiceAndAccount() {
        let backend = InMemoryKeychainBackend()
        var add = baseQuery(account: "a")
        add[kSecValueData as String] = Data("a".utf8)
        backend.add(add as CFDictionary, nil)

        XCTAssertEqual(read(backend, account: "b").0, errSecItemNotFound)

        var otherService = baseQuery(account: "a")
        otherService[kSecAttrService as String] = "app.relay.tests.other"
        otherService[kSecReturnData as String] = true
        var item: CFTypeRef?
        XCTAssertEqual(backend.copyMatching(otherService as CFDictionary, &item), errSecItemNotFound)
    }

    func testPairingSecretStoreRoundTripsThroughInMemoryBackendSemantics() {
        // KeychainPairingSecretStore's delete-then-add pattern must work against the in-memory backend.
        let backend = InMemoryKeychainBackend()
        let match = baseQuery(account: "device-1")
        backend.delete(match as CFDictionary)
        var add = match
        add[kSecValueData as String] = Data(repeating: 7, count: 32)
        XCTAssertEqual(backend.add(add as CFDictionary, nil), errSecSuccess)
        backend.delete(match as CFDictionary)
        add[kSecValueData as String] = Data(repeating: 8, count: 32)
        XCTAssertEqual(backend.add(add as CFDictionary, nil), errSecSuccess)
        XCTAssertEqual(read(backend, account: "device-1").1, Data(repeating: 8, count: 32))
    }
}
