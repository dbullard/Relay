import XCTest
import Network
@testable import Relay

/// Unsigned/ad-hoc test builds (including this test host) can't keep pairing secrets, so
/// they must never send pairing requests to the user's real Relay computers.
@MainActor
final class LANTestBuildPairingTests: XCTestCase {
    func testUnsignedBuildRefusesToPairWithoutContactingThePeer() async throws {
        try XCTSkipIf(Keychain.usesSystemKeychain, "Only meaningful in an unsigned/ad-hoc build")
        let service = LANSharedTabsService(pairingSecretStore: InMemoryPairingSecretStore())
        // An address nothing listens on: if a request were attempted it would fail with a
        // "could not reach" message instead of the test-build one.
        let peer = LANSharedTabsService.Peer(
            endpointKey: "test-peer", deviceId: "TEST-PEER", deviceName: "Booth",
            deviceKind: nil, requiresPairing: true,
            host: "127.0.0.1", port: 9, lastSeen: Date())
        let started = Date()
        let paired = await service.connectToDevice(peer)
        XCTAssertFalse(paired)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5, "Should refuse immediately, without a network request")
        XCTAssertTrue(service.lastPairingFailureMessage?.contains("test build") == true)
    }
}
