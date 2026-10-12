import XCTest
@testable import Relay

final class DiscoveryScanCountersTests: XCTestCase {
    func testConcurrentIncrementsAreNotLost() {
        let counters = DiscoveryScanCounters()
        let iterations = 5000

        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            counters.increment("packets")
        }

        XCTAssertEqual(counters.value("packets"), iterations)
    }

    func testIndependentKeysDoNotInterfere() {
        let counters = DiscoveryScanCounters()

        DispatchQueue.concurrentPerform(iterations: 4000) { i in
            counters.increment(i % 2 == 0 ? "even" : "odd")
        }

        XCTAssertEqual(counters.value("even"), 2000)
        XCTAssertEqual(counters.value("odd"), 2000)
    }

    func testIncrementByAmount() {
        let counters = DiscoveryScanCounters()
        counters.increment("packets", by: 3)
        counters.increment("packets", by: 4)
        XCTAssertEqual(counters.value("packets"), 7)
    }

    func testUnknownKeyReadsZero() {
        let counters = DiscoveryScanCounters()
        XCTAssertEqual(counters.value("nope"), 0)
    }

    func testResetClearsAllValues() {
        let counters = DiscoveryScanCounters()
        counters.increment("packets", by: 5)
        counters.increment("errors", by: 2)
        counters.reset()
        XCTAssertEqual(counters.value("packets"), 0)
        XCTAssertEqual(counters.value("errors"), 0)
    }
}
