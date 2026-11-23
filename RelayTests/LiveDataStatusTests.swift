import XCTest
@testable import Relay

/// Every live tile uses `LiveDataStatus.resolve` to decide whether its data is trustworthy,
/// so frozen data is never shown as if it were live.
final class LiveDataStatusTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 2_000_000)

    func testConnectedWithFreshDataIsLive() {
        let status = LiveDataStatus.resolve(
            isConnected: true, isReconnecting: false,
            lastUpdate: now.addingTimeInterval(-3), staleAfter: 8, now: now
        )
        XCTAssertEqual(status, .live)
    }

    func testConnectedButQuietPastTheThresholdIsStale() {
        let last = now.addingTimeInterval(-9)
        let status = LiveDataStatus.resolve(
            isConnected: true, isReconnecting: false,
            lastUpdate: last, staleAfter: 8, now: now
        )
        XCTAssertEqual(status, .stale(lastUpdate: last))
    }

    func testConnectedWithNoThresholdNeverGoesStale() {
        let status = LiveDataStatus.resolve(
            isConnected: true, isReconnecting: false,
            lastUpdate: now.addingTimeInterval(-3600), staleAfter: nil, now: now
        )
        XCTAssertEqual(status, .live)
    }

    func testConnectedBeforeTheFirstUpdateIsLive() {
        // The tile shows its own "no data yet" message; it isn't stale data.
        let status = LiveDataStatus.resolve(
            isConnected: true, isReconnecting: false,
            lastUpdate: nil, staleAfter: 8, now: now
        )
        XCTAssertEqual(status, .live)
    }

    func testNeverConnectedAndNoErrorIsConnecting() {
        let status = LiveDataStatus.resolve(
            isConnected: false, isReconnecting: false,
            lastUpdate: nil, staleAfter: 8, now: now
        )
        XCTAssertEqual(status, .connecting)
    }

    func testFailureBeforeTheFirstUpdateIsOffline() {
        let status = LiveDataStatus.resolve(
            isConnected: false, isReconnecting: false,
            lastUpdate: nil, staleAfter: 8, reason: "Connection refused", now: now
        )
        XCTAssertEqual(status, .offline(lastUpdate: nil, reason: "Connection refused"))
    }

    func testLostConnectionIsOfflineWithTheLastUpdateKept() {
        let last = now.addingTimeInterval(-30)
        let status = LiveDataStatus.resolve(
            isConnected: false, isReconnecting: false,
            lastUpdate: last, staleAfter: 8, now: now
        )
        XCTAssertEqual(status, .offline(lastUpdate: last, reason: nil))
    }

    func testReconnectingWinsOverOffline() {
        let last = now.addingTimeInterval(-30)
        let status = LiveDataStatus.resolve(
            isConnected: false, isReconnecting: true,
            lastUpdate: last, staleAfter: 8, reason: "Timed out", now: now
        )
        XCTAssertEqual(status, .reconnecting(lastUpdate: last))
    }

    func testAgeText() {
        XCTAssertEqual(LiveDataStatus.ageText(since: now.addingTimeInterval(-12), now: now), "12s ago")
        XCTAssertEqual(LiveDataStatus.ageText(since: now.addingTimeInterval(-245), now: now), "4m ago")
        XCTAssertEqual(LiveDataStatus.ageText(since: now.addingTimeInterval(-7300), now: now), "2h ago")
        XCTAssertEqual(LiveDataStatus.ageText(since: now.addingTimeInterval(5), now: now), "0s ago")
    }

    func testSpokenDescriptionNamesTheStateAgeAndReason() {
        let status = LiveDataStatus.offline(lastUpdate: now.addingTimeInterval(-90), reason: "Network is down")
        XCTAssertEqual(status.spokenDescription(now: now), "Offline, last update 1m ago, Network is down")
    }
}
