import XCTest
@testable import Relay

final class PKCETests: XCTestCase {
    func testRFC7636Vector() {
        // From RFC 7636 appendix B
        XCTAssertEqual(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
    func testVerifierLengthAndAlphabet() {
        let v = PKCE.makeVerifier()
        XCTAssertTrue((43...128).contains(v.count))
        XCTAssertNil(v.range(of: #"[^A-Za-z0-9\-._~]"#, options: .regularExpression))
        XCTAssertNotEqual(v, PKCE.makeVerifier())
    }
}
