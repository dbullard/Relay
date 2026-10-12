import XCTest
@testable import Relay

final class LANRequestSignerTests: XCTestCase {
    private let secret = Data(repeating: 7, count: 32)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func sign(_ method: String = "GET", _ target: String = "/syncedTab/G1?x=1", ts: Int = 1_800_000_000,
                      nonce: String = "n1", body: Data = Data()) -> String {
        LANRequestSigner.signature(secret: secret, method: method, target: target, timestamp: ts, nonce: nonce, body: body)
    }

    private func verify(_ sig: String, _ method: String = "GET", _ target: String = "/syncedTab/G1?x=1",
                        ts: Int = 1_800_000_000, nonce: String = "n1", body: Data = Data(),
                        secret: Data? = nil, at: Date? = nil) -> Bool {
        LANRequestSigner.verify(secret: secret ?? self.secret, signature: sig, method: method, target: target,
                                timestamp: ts, nonce: nonce, body: body, now: at ?? now)
    }

    func testRoundTrip() { XCTAssertTrue(verify(sign())) }
    func testMethodIsCaseInsensitive() { XCTAssertTrue(verify(sign("get"), "GET")) }
    func testTamperedTargetFails() { XCTAssertFalse(verify(sign(), "GET", "/syncedTab/G2?x=1")) }
    func testTamperedQueryFails() { XCTAssertFalse(verify(sign(), "GET", "/syncedTab/G1?x=2")) }
    func testTamperedBodyFails() {
        let sig = sign("POST", "/syncedTab/push", body: Data("a".utf8))
        XCTAssertFalse(verify(sig, "POST", "/syncedTab/push", body: Data("b".utf8)))
    }
    func testWrongSecretFails() { XCTAssertFalse(verify(sign(), secret: Data(repeating: 8, count: 32))) }
    func testStaleTimestampFails() { XCTAssertFalse(verify(sign(), at: now.addingTimeInterval(61))) }
    func testFutureTimestampFails() { XCTAssertFalse(verify(sign(), at: now.addingTimeInterval(-61))) }
    func testWithinSkewPasses() { XCTAssertTrue(verify(sign(), at: now.addingTimeInterval(59))) }
    func testNonceIsPartOfSignature() { XCTAssertFalse(verify(sign(), nonce: "n2")) }
    func testGarbageSignatureFails() { XCTAssertFalse(verify("not-base64!!")) }
    func testPercentEncodedTargetIsSignedVerbatim() {
        let t = "/localPersonPhoto/Ann%20Lee.jpg"
        XCTAssertTrue(verify(sign("GET", t), "GET", t))
        XCTAssertFalse(verify(sign("GET", t), "GET", "/localPersonPhoto/Ann Lee.jpg"))
    }
}
