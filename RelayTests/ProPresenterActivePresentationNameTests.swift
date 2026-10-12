import XCTest
@testable import Relay

@MainActor
final class ProPresenterActivePresentationNameTests: XCTestCase {

    private func decode(_ jsonString: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(jsonString.utf8))
    }

    // Regression test: a real GET /v1/presentation/active response (confirmed against
    // ProPresenter's published OpenAPI spec, and captured live in a 2026-08-09 session log)
    // nests the name under presentation.id.name, not presentation.name. Missing that shape
    // meant this endpoint's response never matched any candidate, so name resolution always
    // fell through to /v1/presentation/focused -- the operator's UI selection, not what's
    // actually live on screen.
    func testExtractsNameFromPresentationActiveShape() throws {
        let json = try decode("""
        {"presentation":{"destination":"presentation","groups":[],"id":{"index":9,"name":"Sermon 08.09.26","uuid":"41EEDA6A-7783-40CE-B1B1-EC20A033B535"},"presentation_path":"/Users/someuser/Documents/ProPresenter/Libraries/Default/Sermon 08.09.26.pro"}}
        """)

        XCTAssertEqual(ProPresenterService.extractPresentationName(from: json), "Sermon 08.09.26")
    }

    func testExtractsNameFromPresentationFocusedShape() throws {
        let json = try decode("""
        {"index":9,"name":"Sermon 08.09.26","uuid":"41EEDA6A-7783-40CE-B1B1-EC20A033B535"}
        """)

        XCTAssertEqual(ProPresenterService.extractPresentationName(from: json), "Sermon 08.09.26")
    }

    func testPresentationActiveShapeTakesPrecedenceOverEmptyTopLevelName() throws {
        let json = try decode("""
        {"presentation":{"groups":[],"id":{"index":2,"name":"Amazing Grace","uuid":"942C3FC3-C4B2-44F7-A55D-4CC913BB8A5D"}}}
        """)

        XCTAssertEqual(ProPresenterService.extractPresentationName(from: json), "Amazing Grace")
    }
}
