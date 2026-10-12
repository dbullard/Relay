import XCTest
@testable import Relay

final class HTTPRequestLimitsTests: XCTestCase {
    private func data(_ s: String) -> Data { Data(s.utf8) }

    func testIncompleteHeadersNeedMore() {
        XCTAssertEqual(HTTPRequestLimits.evaluate(buffer: data("GET / HTTP/1.1\r\nHost: x")), .needMore)
    }

    func testCompleteGetIsReady() {
        XCTAssertEqual(HTTPRequestLimits.evaluate(buffer: data("GET / HTTP/1.1\r\nHost: x\r\n\r\n")), .ready)
    }

    func testBodyShorterThanDeclaredNeedsMore() {
        let req = "POST /x HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc"
        XCTAssertEqual(HTTPRequestLimits.evaluate(buffer: data(req)), .needMore)
    }

    func testBodyCompleteIsReady() {
        let req = "POST /x HTTP/1.1\r\nContent-Length: 3\r\n\r\nabc"
        XCTAssertEqual(HTTPRequestLimits.evaluate(buffer: data(req)), .ready)
    }

    func testHugeDeclaredBodyRejectedImmediately() {
        let req = "POST /x HTTP/1.1\r\nContent-Length: 4000000000\r\n\r\n"
        XCTAssertEqual(HTTPRequestLimits.evaluate(buffer: data(req)), .bodyTooLarge)
    }

    func testNegativeOrGarbageContentLengthIsMalformed() {
        XCTAssertEqual(HTTPRequestLimits.evaluate(buffer: data("POST /x HTTP/1.1\r\nContent-Length: -5\r\n\r\n")), .malformed)
        XCTAssertEqual(HTTPRequestLimits.evaluate(buffer: data("POST /x HTTP/1.1\r\nContent-Length: abc\r\n\r\n")), .malformed)
    }

    func testEndlessHeadersRejected() {
        let junk = String(repeating: "A", count: HTTPRequestLimits.maxHeaderBytes + 1)
        XCTAssertEqual(HTTPRequestLimits.evaluate(buffer: data("GET / HTTP/1.1\r\nX: \(junk)")), .headersTooLarge)
    }
}
