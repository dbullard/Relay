import XCTest
@testable import Relay

final class TranscriptionFailureTests: XCTestCase {
    func testErrorDescriptionMatchesMessage() {
        let failure = TranscriptionFailure(code: .permissionDenied, message: "Speech recognition permission was denied.")
        XCTAssertEqual(failure.errorDescription, "Speech recognition permission was denied.")
        XCTAssertEqual(failure.localizedDescription, "Speech recognition permission was denied.")
    }

    func testCodeRawValuesAreStable() {
        // These values cross the XPC wire as plain Int32 -- if this enum is ever
        // reordered without noticing the raw values are load-bearing, this test
        // catches it.
        XCTAssertEqual(TranscriptionErrorCode.success.rawValue, 0)
        XCTAssertEqual(TranscriptionErrorCode.unknown.rawValue, 1)
        XCTAssertEqual(TranscriptionErrorCode.permissionDenied.rawValue, 2)
        XCTAssertEqual(TranscriptionErrorCode.recognizerUnavailable.rawValue, 3)
        XCTAssertEqual(TranscriptionErrorCode.onDeviceUnsupported.rawValue, 4)
        XCTAssertEqual(TranscriptionErrorCode.recognitionFailed.rawValue, 5)
        XCTAssertEqual(TranscriptionErrorCode.connectionUnavailable.rawValue, 6)
    }
}
