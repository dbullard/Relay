import XCTest

final class DAWTransportLogFixtureTests: XCTestCase {

    func testExtractsRecvBytePacketsInOrder() throws {
        let log = """
        [DAWTransport] daw=proToolsHUI protocol=HUI input="Automatic" output="Automatic" counterSource=automatic appendMTC=false
        [DAWTransport] recv source=-42684340 bytes=90 00 00
        [DAWTransport] HUI ping reply daw=proToolsHUI
        [DAWTransport] recv source=-42684340 bytes=F0 00 00 66 05 00 11 05 05 F7
        """

        let packets = try DAWTransportLogFixture.packets(from: log)

        XCTAssertEqual(packets, [
            [0x90, 0x00, 0x00],
            [0xF0, 0x00, 0x00, 0x66, 0x05, 0x00, 0x11, 0x05, 0x05, 0xF7]
        ])
    }

    func testIgnoresNonRecvLines() throws {
        let log = """
        [DAWTransport] send daw=proToolsHUI protocol=HUI command=play
        [DAWTransport] HUI ping reply daw=proToolsHUI
        """

        let packets = try DAWTransportLogFixture.packets(from: log, allowEmpty: true)

        XCTAssertTrue(packets.isEmpty)
    }

    func testRejectsMalformedHex() {
        let log = "[DAWTransport] recv source=1 bytes=F0 00 XX F7"

        XCTAssertThrowsError(try DAWTransportLogFixture.packets(from: log)) { error in
            XCTAssertEqual(String(describing: error), "malformedHexToken(\"XX\", line: 1)")
        }
    }

    func testRejectsEmptyReplayFixturesByDefault() {
        XCTAssertThrowsError(try DAWTransportLogFixture.packets(from: "noise only")) { error in
            XCTAssertEqual(String(describing: error), "emptyFixture")
        }
    }
}
