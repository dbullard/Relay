import XCTest
@testable import Relay

/// Button tiles show "Done" or a failure from `OSCManager.send`'s result, so a message
/// that can never leave the app must report false instead of failing silently.
final class OSCManagerSendResultTests: XCTestCase {
    func testSendRejectsAnAddressWithoutLeadingSlash() {
        let sent = OSCManager.shared.send(
            to: OSCEndpoint(host: "127.0.0.1", port: 9),
            message: OSCMessage(address: "cue/go", args: [])
        )
        XCTAssertFalse(sent)
    }

    func testSendRejectsAMissingHost() {
        let sent = OSCManager.shared.send(
            to: OSCEndpoint(host: "  ", port: 9),
            message: OSCMessage(address: "/cue/go", args: [])
        )
        XCTAssertFalse(sent)
    }

    func testSendRejectsPortZero() {
        let sent = OSCManager.shared.send(
            to: OSCEndpoint(host: "127.0.0.1", port: 0),
            message: OSCMessage(address: "/cue/go", args: [])
        )
        XCTAssertFalse(sent)
    }

    func testSendAcceptsAValidMessage() {
        // Port 9 is the discard service; UDP gives no delivery confirmation either way.
        let sent = OSCManager.shared.send(
            to: OSCEndpoint(host: "127.0.0.1", port: 9),
            message: OSCMessage(address: "/cue/go", args: [])
        )
        XCTAssertTrue(sent)
    }
}
