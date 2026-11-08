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

    func testNotConfiguredOAuthErrorPointsToDocs() {
        let message = OAuthService.OAuthError.notConfigured.errorDescription ?? ""
        XCTAssertTrue(message.contains("PCO_OAUTH_CLIENT_ID"))
        XCTAssertTrue(message.contains("docs/INTEGRATIONS.md"))
    }

    func testStartLoginWithoutClientIDThrowsNotConfigured() async {
        let service = OAuthService(clientID: "", tokenStore: KeychainTokenStore())
        do {
            try await service.startLogin()
            XCTFail("Expected notConfigured")
        } catch let error as OAuthService.OAuthError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
