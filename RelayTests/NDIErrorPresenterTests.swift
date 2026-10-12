import XCTest
@testable import Relay

final class NDIErrorPresenterTests: XCTestCase {

    func test_idle_returnsNoSourceSelected() {
        let p = NDIErrorPresenter.presentation(for: .idle, sourceName: nil, retryCount: 0)
        XCTAssertEqual(p?.headline, "No Source Selected")
        XCTAssertEqual(p?.subtitle, "Choose an NDI source in settings.")
        XCTAssertNil(p?.recoveryAction)
    }

    func test_connecting_showsSourceName() {
        let p = NDIErrorPresenter.presentation(for: .connecting, sourceName: "Program Feed", retryCount: 0)
        XCTAssertEqual(p?.headline, "Connecting…")
        XCTAssertEqual(p?.subtitle, "Program Feed")
    }

    func test_connected_returnsNilPresentation() {
        let p = NDIErrorPresenter.presentation(for: .connected, sourceName: nil, retryCount: 0)
        XCTAssertNil(p)
    }

    func test_suspendedHiddenTile_returnsCorrectCopy() {
        let p = NDIErrorPresenter.presentation(for: .suspended(.hiddenTile), sourceName: nil, retryCount: 0)
        XCTAssertEqual(p?.headline, "Paused")
        XCTAssertEqual(p?.subtitle, "Stream resumes when this tile is visible.")
    }

    func test_suspendedOverBudget_returnsCorrectCopy() {
        let p = NDIErrorPresenter.presentation(for: .suspended(.overBudget), sourceName: nil, retryCount: 0)
        XCTAssertEqual(p?.headline, "Inactive")
        XCTAssertEqual(p?.subtitle, "Two NDI modules are already active on this tab.")
    }

    func test_failed_zeroRetry_showsReconnectingBadge() {
        let p = NDIErrorPresenter.presentation(for: .failed("initial failure"), sourceName: nil, retryCount: 0)
        XCTAssertEqual(p?.headline, "Reconnecting…")
        XCTAssertNil(p?.recoveryAction)
    }

    func test_failed_earlyRetry_showsReconnectingBadge() {
        let p = NDIErrorPresenter.presentation(for: .failed("raw sdk error"), sourceName: nil, retryCount: 1)
        XCTAssertEqual(p?.headline, "Reconnecting…")
        XCTAssertNil(p?.recoveryAction)
    }

    func test_failed_lateRetry_showsRetryButton() {
        let p = NDIErrorPresenter.presentation(for: .failed("raw sdk error"), sourceName: nil, retryCount: 4)
        XCTAssertEqual(p?.headline, "Source Unavailable")
        XCTAssertNotNil(p?.recoveryAction)
    }

    func test_sanitizesUnknownError() {
        let p = NDIErrorPresenter.presentation(for: .failed("NDK_ERR_4029: socket closed"), sourceName: nil, retryCount: 4)
        XCTAssertEqual(p?.subtitle, "The source stopped responding. Relay will keep trying.")
    }
}
