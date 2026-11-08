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
        XCTAssertTrue(message.contains("Settings > Integrations"))
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

final class ServiceCredentialsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "ServiceCredentialsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func test_enteredValueWinsAndIsTrimmed() {
        let defaults = makeDefaults()
        ServiceCredentials.set("  abc123  ", forKey: "k", defaults: defaults)
        XCTAssertEqual(ServiceCredentials.resolved(defaultsKey: "k", plistKeys: ["MISSING"], defaults: defaults), "abc123")
    }

    func test_emptyOrUnsetFallsBackToBlank() {
        let defaults = makeDefaults()
        XCTAssertEqual(ServiceCredentials.resolved(defaultsKey: "k", plistKeys: ["MISSING"], defaults: defaults), "")
        ServiceCredentials.set("x", forKey: "k", defaults: defaults)
        ServiceCredentials.set("   ", forKey: "k", defaults: defaults)
        XCTAssertNil(defaults.string(forKey: "k"))
    }
}
