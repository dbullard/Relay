import XCTest
@testable import Relay

final class YouTubeOAuthStateTests: XCTestCase {
    func testMatchingState() {
        XCTAssertTrue(YouTubeOAuthState.matches(callbackURL: URL(string: "http://127.0.0.1:55951/?code=c&state=abc")!, expected: "abc"))
    }
    func testMissingStateRejected() {
        XCTAssertFalse(YouTubeOAuthState.matches(callbackURL: URL(string: "http://127.0.0.1:55951/?code=c")!, expected: "abc"))
    }
    func testWrongStateRejected() {
        XCTAssertFalse(YouTubeOAuthState.matches(callbackURL: URL(string: "http://127.0.0.1:55951/?code=c&state=zzz")!, expected: "abc"))
    }
    func testGeneratedStateIsLongAndUnique() {
        let a = YouTubeOAuthState.make(), b = YouTubeOAuthState.make()
        XCTAssertGreaterThanOrEqual(a.count, 32)
        XCTAssertNotEqual(a, b)
    }
}
