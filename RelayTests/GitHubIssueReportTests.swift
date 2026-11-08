import XCTest
@testable import Relay

final class GitHubIssueReportTests: XCTestCase {
    private let info: [String: Any] = ["CFBundleShortVersionString": "2.0", "CFBundleVersion": "7"]

    private func items(_ url: URL) -> [String: String] {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return Dictionary(uniqueKeysWithValues: (comps?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    func test_emptyMessageProducesNoReport() {
        XCTAssertNil(GitHubIssueReport.make(message: "  \n", diagnostics: nil, info: info))
    }

    func test_prefillsIssueFormFields() throws {
        let report = try XCTUnwrap(GitHubIssueReport.make(message: "Crash when adding a tile", diagnostics: "short log", info: info))
        let q = items(report.url)
        XCTAssertEqual(report.url.host, "github.com")
        XCTAssertEqual(q["template"], "bug_report.yml")
        XCTAssertEqual(q["version"], "Relay 2.0 (7)")
        XCTAssertEqual(q["actual"], "Crash when adding a tile")
        XCTAssertEqual(q["evidence"], "short log")
        XCTAssertFalse(report.diagnosticsNeedPasting)
    }

    func test_longDiagnosticsAreNotPutInTheLink() throws {
        let long = String(repeating: "x", count: GitHubIssueReport.maxInlineDiagnosticsLength + 1)
        let report = try XCTUnwrap(GitHubIssueReport.make(message: "Bug", diagnostics: long, info: info))
        XCTAssertTrue(report.diagnosticsNeedPasting)
        XCTAssertFalse(report.url.absoluteString.contains(long))
    }
}
