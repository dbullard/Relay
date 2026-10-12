import XCTest
@testable import Relay

final class ShureReconnectBackoffTests: XCTestCase {

    func testFirstAttemptUsesBaseDelay() {
        XCTAssertEqual(ShureReconnectBackoff.delay(forAttempt: 1), 1.0)
    }

    func testDelayDoublesEachAttempt() {
        XCTAssertEqual(ShureReconnectBackoff.delay(forAttempt: 2), 2.0)
        XCTAssertEqual(ShureReconnectBackoff.delay(forAttempt: 3), 4.0)
        XCTAssertEqual(ShureReconnectBackoff.delay(forAttempt: 4), 8.0)
        XCTAssertEqual(ShureReconnectBackoff.delay(forAttempt: 5), 16.0)
        XCTAssertEqual(ShureReconnectBackoff.delay(forAttempt: 6), 32.0)
    }

    func testDelayCapsAtSixtySeconds() {
        XCTAssertEqual(ShureReconnectBackoff.delay(forAttempt: 7), 60.0)
        XCTAssertEqual(ShureReconnectBackoff.delay(forAttempt: 20), 60.0)
        XCTAssertEqual(ShureReconnectBackoff.delay(forAttempt: 1000), 60.0)
    }

    func testNonPositiveAttemptFallsBackToBaseDelay() {
        XCTAssertEqual(ShureReconnectBackoff.delay(forAttempt: 0), 1.0)
        XCTAssertEqual(ShureReconnectBackoff.delay(forAttempt: -3), 1.0)
    }
}
