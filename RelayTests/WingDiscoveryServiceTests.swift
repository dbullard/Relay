import XCTest
@testable import Relay

final class WingDiscoveryServiceTests: XCTestCase {
    private func makeReply(_ csv: String) -> OSCMessage {
        OSCMessage(address: "/?", args: [.string(csv)])
    }

    func testParseWingInfoExtractsNameAndModel() {
        let message = makeReply("WING,10.0.0.50,FOH Wing,WING,SN12345,3.0.6")
        let result = WingDiscoveryService.parseWingInfo(message: message, sourceIP: "10.0.0.50")
        XCTAssertEqual(result?.ipAddress, "10.0.0.50")
        XCTAssertEqual(result?.name, "FOH Wing")
        XCTAssertEqual(result?.model, "WING")
    }

    func testParseWingInfoReturnsNilForTooFewFields() {
        let message = makeReply("WING,10.0.0.50")
        XCTAssertNil(WingDiscoveryService.parseWingInfo(message: message, sourceIP: "10.0.0.50"))
    }

    func testParseWingInfoReturnsNilForNonStringArg() {
        let message = OSCMessage(address: "/?", args: [.int32(1)])
        XCTAssertNil(WingDiscoveryService.parseWingInfo(message: message, sourceIP: "10.0.0.50"))
    }

    func testParseWingInfoReturnsNilWhenNameIsEmpty() {
        let message = makeReply("WING,10.0.0.50,,WING,SN12345,3.0.6")
        XCTAssertNil(WingDiscoveryService.parseWingInfo(message: message, sourceIP: "10.0.0.50"))
    }
}
