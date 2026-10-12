import XCTest
@testable import Relay

final class OSCCodecTests: XCTestCase {
    func testEncodeGrandMA3CommandUsesAddressAndStringArgument() {
        let data = OSCCodec.encode(
            message: OSCMessage(address: "/cmd", args: [.string("Call Plugin 1")])
        )

        XCTAssertEqual(
            data,
            Data([47, 99, 109, 100, 0, 0, 0, 0, 44, 115, 0, 0,
                  67, 97, 108, 108, 32, 80, 108, 117, 103, 105, 110, 32,
                  49, 0, 0, 0])
        )
    }

    func testEncodeTypeOnlyArgumentsHaveNoPayloadBytes() {
        let data = OSCCodec.encode(
            message: OSCMessage(address: "/x", args: [.bool(true), .bool(false), .null, .impulse])
        )

        XCTAssertEqual(data, Data([47, 120, 0, 0, 44, 84, 70, 78, 73, 0, 0, 0]))
    }

    func testEncodeTimetagWritesEightByteBigEndianPayload() {
        let data = OSCCodec.encode(
            message: OSCMessage(address: "/t", args: [.timetag(0x0102_0304_0506_0708)])
        )

        XCTAssertEqual(data.suffix(8), Data([1, 2, 3, 4, 5, 6, 7, 8]))
    }
}
