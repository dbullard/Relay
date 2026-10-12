import XCTest
@testable import Relay

#if canImport(Darwin)
import Darwin
#endif

final class NetworkUtilsSocketTests: XCTestCase {
    func testMakeSocketNonBlockingSetsTheFlag() {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }

        XCTAssertTrue(NetworkUtils.makeSocketNonBlocking(fd))

        let flags = fcntl(fd, F_GETFL, 0)
        XCTAssertNotEqual(flags & O_NONBLOCK, 0, "expected O_NONBLOCK to be set after makeSocketNonBlocking")
    }

    func testMakeSocketNonBlockingReturnsFalseForInvalidDescriptor() {
        XCTAssertFalse(NetworkUtils.makeSocketNonBlocking(-1))
    }

    func testNonBlockingRecvReturnsImmediatelyWhenNoDataIsQueued() {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd) }
        XCTAssertTrue(NetworkUtils.makeSocketNonBlocking(fd))

        // Safety belt: if makeSocketNonBlocking regresses to a no-op, recv() below would
        // otherwise block forever with no peer ever sending data. This timeout turns that
        // into a slow, clearly-failing assertion instead of hanging the test run.
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var buffer = [UInt8](repeating: 0, count: 16)
        let start = Date()
        let received = recv(fd, &buffer, buffer.count, 0)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(received, -1)
        XCTAssertEqual(errno, EWOULDBLOCK)
        XCTAssertLessThan(elapsed, 0.1, "a non-blocking recv on an empty socket must return immediately, not block")
    }
}
