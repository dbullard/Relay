import XCTest
@testable import Relay

@MainActor
final class LANPairingHandshakeTests: XCTestCase {
    private func reset() {
        let d = UserDefaults.standard
        for k in ["lan_sharing_enabled", "lan_allow_unpaired_read", "lan_browser_view_only_enabled",
                  "lan_paired_devices", "lan_allow_legacy_unsigned"] { d.removeObject(forKey: k) }
    }

    private func post(_ path: String, json: String, deviceId: String = "JOINER-1") -> String {
        let body = Data(json.utf8)
        return "POST \(path) HTTP/1.1\r\nHost: relay.local\r\nX-Relay-Device-Id: \(deviceId)\r\nContent-Length: \(body.count)\r\n\r\n\(json)"
    }
    private func get(_ path: String) -> String { "GET \(path) HTTP/1.1\r\nHost: relay.local\r\n\r\n" }
    private func bodyJSON(_ data: Data) -> [String: Any] {
        let s = String(decoding: data, as: UTF8.self)
        guard let r = s.range(of: "\r\n\r\n"),
              let obj = try? JSONSerialization.jsonObject(with: Data(s[r.upperBound...].utf8)) as? [String: Any] else { return [:] }
        return obj
    }

    func testHostReturnsPublicKeyAndSecretIsStoredOnApprove() throws {
        reset()
        let store = InMemoryPairingSecretStore()
        let host = LANSharedTabsService(pairingSecretStore: store)
        let joiner = LANPairingKeyAgreement.makeKeyPair()
        let json = #"{"requestId":"R1","deviceId":"JOINER-1","deviceName":"Booth","reason":"join","publicKey":"\#(joiner.publicBase64)"}"#

        let resp = bodyJSON(host.route(request: post("/pair/request", json: json)))
        XCTAssertEqual(resp["status"] as? String, "pending")
        let hostPub = try XCTUnwrap(resp["hostPublicKey"] as? String)

        let pending = try XCTUnwrap(host.pendingPairingRequests.first)
        let sas = try XCTUnwrap(host.shortAuthString(for: pending))
        host.approvePairingRequest(pending)

        let joinerSecret = try LANPairingKeyAgreement.deriveSecret(privateKey: joiner.privateKey, peerPublicBase64: hostPub, requestId: "R1")
        XCTAssertEqual(store.secret(for: "JOINER-1"), joinerSecret)
        XCTAssertEqual(sas, LANPairingKeyAgreement.shortAuthString(joinerPublicBase64: joiner.publicBase64, hostPublicBase64: hostPub, secret: joinerSecret))

        let status = bodyJSON(host.route(request: get("/pair/status?requestId=R1")))
        XCTAssertEqual(status["status"] as? String, "approved")
        XCTAssertEqual(status["hostPublicKey"] as? String, hostPub)
    }

    func testLegacyRequestWithoutPublicKeyStillWorksAndStoresNoSecret() throws {
        reset()
        let store = InMemoryPairingSecretStore()
        let host = LANSharedTabsService(pairingSecretStore: store)
        let json = #"{"requestId":"R2","deviceId":"OLD-1","deviceName":"Old Mac","reason":"join"}"#
        let resp = bodyJSON(host.route(request: post("/pair/request", json: json, deviceId: "OLD-1")))
        XCTAssertEqual(resp["status"] as? String, "pending")
        XCTAssertNil(resp["hostPublicKey"])
        host.approvePairingRequest(try XCTUnwrap(host.pendingPairingRequests.first))
        XCTAssertNil(store.secret(for: "OLD-1"))
    }

    func testSpoofedRepairOfDeviceWithSecretIsNotAutoApproved() throws {
        reset()
        let store = InMemoryPairingSecretStore()
        let host = LANSharedTabsService(pairingSecretStore: store)
        let joiner = LANPairingKeyAgreement.makeKeyPair()
        _ = host.route(request: post("/pair/request", json: #"{"requestId":"R3","deviceId":"JOINER-1","deviceName":"Booth","reason":"join","publicKey":"\#(joiner.publicBase64)"}"#))
        host.approvePairingRequest(try XCTUnwrap(host.pendingPairingRequests.first))
        let originalSecret = try XCTUnwrap(store.secret(for: "JOINER-1"))

        let attacker = LANPairingKeyAgreement.makeKeyPair()
        let resp = bodyJSON(host.route(request: post("/pair/request", json: #"{"requestId":"R4","deviceId":"JOINER-1","deviceName":"Booth","reason":"join","publicKey":"\#(attacker.publicBase64)"}"#)))
        XCTAssertEqual(resp["status"] as? String, "pending", "must prompt, not auto-approve")
        XCTAssertEqual(store.secret(for: "JOINER-1"), originalSecret, "secret must not change before a human approves")
    }
}
