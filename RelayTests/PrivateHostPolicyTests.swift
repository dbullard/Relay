import XCTest
@testable import Relay

final class PrivateHostPolicyTests: XCTestCase {
    func testPrivateAddressesAllowed() {
        for h in ["10.0.0.5", "172.16.0.1", "172.31.255.255", "192.168.1.20", "169.254.3.4", "127.0.0.1", "::1", "fe80::1", "fd12:3456::1", "shure-ulxd.local"] {
            XCTAssertTrue(PrivateHostPolicy.isPrivateOrLocal(h), h)
        }
    }
    func testPublicAddressesRejected() {
        for h in ["8.8.8.8", "172.32.0.1", "172.15.0.1", "192.169.1.1", "example.com", "evil.local.example.com", ""] {
            XCTAssertFalse(PrivateHostPolicy.isPrivateOrLocal(h), h)
        }
    }
}
