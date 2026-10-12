import XCTest
@testable import Relay

final class PCOOAuthErrorTests: XCTestCase {
    func testCancelledOAuthErrorHasFriendlyDescription() {
        let error = OAuthService.OAuthError.cancelled
        XCTAssertEqual(error.errorDescription, "Sign-in canceled.")
        XCTAssertFalse(error.localizedDescription.contains("OAuthError error 1"))
    }

    func testMissingCodeOAuthErrorHasFriendlyDescription() {
        let error = OAuthService.OAuthError.missingCode
        XCTAssertEqual(error.errorDescription, "Planning Center did not return an authorization code.")
    }
}
