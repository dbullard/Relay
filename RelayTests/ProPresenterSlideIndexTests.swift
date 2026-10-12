import XCTest
@testable import Relay

@MainActor
final class ProPresenterSlideIndexTests: XCTestCase {

    private func decode(_ jsonString: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(jsonString.utf8))
    }

    // GET /v1/presentation/slide_index is the only authoritative slide position.
    func testExtractsIndexFromSlideIndexShape() throws {
        let json = try decode("""
        {"presentation_index":{"index":5,"presentation_id":{"uuid":"942C3FC3-C4B2-44F7-A55D-4CC913BB8A5D","name":"Amazing Grace","index":2}}}
        """)
        XCTAssertEqual(ProPresenterService.extractSlideIndex(from: json), 5)
    }

    func testIndexZeroIsValid() throws {
        let json = try decode(#"{"presentation_index":{"index":0,"presentation_id":{"uuid":"x","name":"y","index":9}}}"#)
        XCTAssertEqual(ProPresenterService.extractSlideIndex(from: json), 0)
    }

    // Nothing live: ProPresenter returns a null presentation_index.
    func testNullPresentationIndexYieldsNil() throws {
        XCTAssertNil(ProPresenterService.extractSlideIndex(from: try decode(#"{"presentation_index":null}"#)))
    }

    // Regression: the playlist-item index nested in presentation.id must never be mistaken
    // for the slide index (it was, and it fed every group/slide-number lookup).
    func testPlaylistItemIndexIsNotASlideIndex() throws {
        let active = try decode(#"{"presentation":{"groups":[],"id":{"index":9,"name":"Sermon","uuid":"41EEDA6A"}}}"#)
        XCTAssertNil(ProPresenterService.extractSlideIndex(from: active))
    }

    func testNegativeIndexRejected() throws {
        XCTAssertNil(ProPresenterService.extractSlideIndex(from: try decode(#"{"presentation_index":{"index":-1}}"#)))
    }
}
