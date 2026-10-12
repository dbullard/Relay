import XCTest
@testable import Relay

final class PairingInputSanitizerTests: XCTestCase {
    func testStripsControlCharactersAndNewlines() {
        XCTAssertEqual(PairingInputSanitizer.deviceName("Booth\n\u{0007}Mac\t"), "BoothMac")
    }
    func testTrimsAndCapsLength() {
        let long = String(repeating: "A", count: 500)
        XCTAssertEqual(PairingInputSanitizer.deviceName("  \(long)  ").count, 40)
    }
    func testEmptyFallsBackToUnknownDevice() {
        XCTAssertEqual(PairingInputSanitizer.deviceName("  \n "), "Unknown device")
    }
    func testPlainNameUnchanged() {
        XCTAssertEqual(PairingInputSanitizer.deviceName("David's MacBook Pro"), "David's MacBook Pro")
    }
}
