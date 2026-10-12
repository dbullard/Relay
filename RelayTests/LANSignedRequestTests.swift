import XCTest
@testable import Relay

@MainActor
final class LANSignedRequestTests: XCTestCase {
    private let deviceId = "SIGNED-CLIENT"
    private let secret = Data(repeating: 9, count: 32)

    private func prepare(legacyAllowed: Bool? = nil, withSecret: Bool = true) -> LANSharedTabsService {
        let d = UserDefaults.standard
        for k in ["lan_sharing_enabled", "lan_allow_unpaired_read", "lan_browser_view_only_enabled", "lan_allow_legacy_unsigned"] { d.removeObject(forKey: k) }
        if let legacyAllowed { d.set(legacyAllowed, forKey: "lan_allow_legacy_unsigned") }
        DevicePairingStore.save(DevicePairingStore.setEnabled(true, deviceId: deviceId, deviceName: "C", deviceKind: nil, in: [:]))
        let store = InMemoryPairingSecretStore()
        if withSecret { store.setSecret(secret, for: deviceId) }
        return LANSharedTabsService(pairingSecretStore: store)
    }

    private func request(method: String = "GET", target: String = "/syncedPresence", body: Data = Data(),
                         signWith key: Data? = nil, ts: Int? = nil, nonce: String = UUID().uuidString) -> String {
        var s = "\(method) \(target) HTTP/1.1\r\nHost: relay.local\r\nX-Relay-Device-Id: \(deviceId)\r\n"
        if let key {
            let t = ts ?? Int(Date().timeIntervalSince1970)
            let sig = LANRequestSigner.signature(secret: key, method: method, target: target, timestamp: t, nonce: nonce, body: body)
            s += "X-Relay-Timestamp: \(t)\r\nX-Relay-Nonce: \(nonce)\r\nX-Relay-Signature: \(sig)\r\n"
        }
        s += "Content-Length: \(body.count)\r\n\r\n" + String(decoding: body, as: UTF8.self)
        return s
    }
    private func status(_ d: Data) -> String { String(decoding: d, as: UTF8.self).components(separatedBy: "\r\n").first ?? "" }

    func testSignedRequestAccepted() {
        let s = prepare()
        XCTAssertTrue(status(s.route(request: request(signWith: secret))).contains("204"))
    }
    func testUnsignedRequestFromDeviceWithSecretRejectedEvenWhenLegacyAllowed() {
        let s = prepare(legacyAllowed: true)
        XCTAssertTrue(status(s.route(request: request())).contains("401"))
    }
    func testWrongSecretRejected() {
        let s = prepare()
        XCTAssertTrue(status(s.route(request: request(signWith: Data(repeating: 1, count: 32)))).contains("401"))
    }
    func testReplayedNonceRejected() {
        let s = prepare()
        let r = request(signWith: secret, nonce: "fixed-nonce")
        XCTAssertTrue(status(s.route(request: r)).contains("204"))
        XCTAssertTrue(status(s.route(request: r)).contains("401"))
    }
    func testStaleTimestampRejected() {
        let s = prepare()
        XCTAssertTrue(status(s.route(request: request(signWith: secret, ts: Int(Date().timeIntervalSince1970) - 600))).contains("401"))
    }
    func testTamperedPathRejected() {
        let s = prepare()
        let signedForPresence = request(signWith: secret)
        let tampered = signedForPresence.replacingOccurrences(of: "GET /syncedPresence", with: "GET /syncedTab/G1")
        XCTAssertTrue(status(s.route(request: tampered)).contains("401"))
    }
    func testLegacyUnsignedAllowedForDeviceWithoutSecretWhenFlagOn() {
        let s = prepare(legacyAllowed: true, withSecret: false)
        XCTAssertTrue(status(s.route(request: request())).contains("204"))
    }
    func testLegacyUnsignedRejectedForDeviceWithoutSecretWhenFlagOff() {
        let s = prepare(legacyAllowed: false, withSecret: false)
        XCTAssertTrue(status(s.route(request: request())).contains("401"))
    }
    func testSignedPostBodyIsCovered() {
        let s = prepare()
        let body = Data("{\"x\":1}".utf8)
        var r = request(method: "POST", target: "/syncedPresence", body: body, signWith: secret)
        r = r.replacingOccurrences(of: "{\"x\":1}", with: "{\"x\":2}")
        XCTAssertTrue(status(s.route(request: r)).contains("401"))
    }
    func testSigningTargetKeepsPercentEncoding() {
        XCTAssertEqual(LANSharedTabsService.signingTarget(for: URL(string: "http://h:1/localPersonPhoto/Ann%20Lee.jpg?a=b%20c")!),
                       "/localPersonPhoto/Ann%20Lee.jpg?a=b%20c")
    }
}
