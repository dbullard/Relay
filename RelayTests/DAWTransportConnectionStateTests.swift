import XCTest
@testable import Relay

final class DAWTransportConnectionStateTests: XCTestCase {

    func testFreshSignalIsAlwaysConnectedRegardlessOfPlayState() {
        XCTAssertEqual(
            DAWTransportConnectionState.resolved(
                hasFreshSignal: true,
                hasStaleSignal: false,
                hasKnownTransportPlayState: true,
                isPlaying: false
            ),
            .connected
        )
        XCTAssertEqual(
            DAWTransportConnectionState.resolved(
                hasFreshSignal: true,
                hasStaleSignal: false,
                hasKnownTransportPlayState: false,
                isPlaying: true
            ),
            .connected
        )
    }

    func testStaleSignalWithKnownStoppedPlayStateIsPaused() {
        XCTAssertEqual(
            DAWTransportConnectionState.resolved(
                hasFreshSignal: false,
                hasStaleSignal: true,
                hasKnownTransportPlayState: true,
                isPlaying: false
            ),
            .paused
        )
    }

    func testStaleSignalWithKnownPlayingStateIsStale() {
        XCTAssertEqual(
            DAWTransportConnectionState.resolved(
                hasFreshSignal: false,
                hasStaleSignal: true,
                hasKnownTransportPlayState: true,
                isPlaying: true
            ),
            .stale
        )
    }

    func testStaleSignalWithUnknownPlayStateFallsBackToStale() {
        XCTAssertEqual(
            DAWTransportConnectionState.resolved(
                hasFreshSignal: false,
                hasStaleSignal: true,
                hasKnownTransportPlayState: false,
                isPlaying: false
            ),
            .stale
        )
    }

    func testNoSignalHistoryIsDisconnected() {
        XCTAssertEqual(
            DAWTransportConnectionState.resolved(
                hasFreshSignal: false,
                hasStaleSignal: false,
                hasKnownTransportPlayState: true,
                isPlaying: false
            ),
            .disconnected
        )
    }

    func testPausedStateHasCalmStyling() {
        XCTAssertEqual(DAWTransportConnectionState.paused.title, "Paused")
        XCTAssertEqual(DAWTransportConnectionState.paused.systemImage, "pause.circle.fill")
    }
}
