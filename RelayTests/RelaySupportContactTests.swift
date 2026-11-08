import XCTest
@testable import Relay

final class RelaySupportContactTests: XCTestCase {
    private func bodyValue(of url: URL?) -> String? {
        guard let url else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "body" })?
            .value
    }

    func test_supportEmailURL_withoutContext_bodyIsDiagnosticSummaryOnly() {
        let url = RelaySupportContact.supportEmailURL(context: nil, diagnosticSummary: "App: Relay\nVersion: 1.2")

        XCTAssertEqual(bodyValue(of: url), "App: Relay\nVersion: 1.2")
    }

    func test_supportEmailURL_withContext_prependsContextBeforeDiagnosticSummary() {
        let url = RelaySupportContact.supportEmailURL(
            context: "Purchase error: timeout",
            diagnosticSummary: "App: Relay\nVersion: 1.2"
        )

        XCTAssertEqual(bodyValue(of: url), "Purchase error: timeout\n\nApp: Relay\nVersion: 1.2")
    }

    func test_supportEmailURL_emptyContextTreatedSameAsNil() {
        let withEmpty = RelaySupportContact.supportEmailURL(context: "", diagnosticSummary: "summary")
        let withNil = RelaySupportContact.supportEmailURL(context: nil, diagnosticSummary: "summary")

        XCTAssertEqual(bodyValue(of: withEmpty), bodyValue(of: withNil))
        XCTAssertEqual(bodyValue(of: withNil), "summary")
    }

    func test_supportEmailURL_setsCorrectRecipientSchemeAndSubject() {
        let url = RelaySupportContact.supportEmailURL(context: nil, diagnosticSummary: "summary")

        XCTAssertEqual(url?.scheme, "mailto")
        let components = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        XCTAssertEqual(components?.path, RelaySupportContact.supportEmail)
        let subject = components?.queryItems?.first(where: { $0.name == "subject" })?.value
        XCTAssertEqual(subject, "Relay Support Request")
    }

    func test_helpCenterURL_isExpectedAddress() {
        XCTAssertEqual(RelaySupportContact.helpCenterURL.absoluteString, "https://github.com/dbullard/Relay")
    }
}
