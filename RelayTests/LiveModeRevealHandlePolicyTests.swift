import XCTest
import CoreGraphics
@testable import Relay

final class LiveModeRevealHandlePolicyTests: XCTestCase {

    func testVisibleOnlyInLiveModeWhileChromeHidden() {
        XCTAssertTrue(LiveModeRevealHandlePolicy.isVisible(isLiveMode: true, isChromeVisible: false))
        XCTAssertFalse(LiveModeRevealHandlePolicy.isVisible(isLiveMode: true, isChromeVisible: true))
        XCTAssertFalse(LiveModeRevealHandlePolicy.isVisible(isLiveMode: false, isChromeVisible: false))
        XCTAssertFalse(LiveModeRevealHandlePolicy.isVisible(isLiveMode: false, isChromeVisible: true))
    }

    func testSpecValues() {
        XCTAssertEqual(LiveModeRevealHandlePolicy.hotZoneHeight, 28)
        XCTAssertEqual(LiveModeRevealHandlePolicy.pillSize, CGSize(width: 44, height: 6))
        XCTAssertEqual(LiveModeRevealHandlePolicy.tapTargetSize, CGSize(width: 60, height: 44), "44 pt minimum touch target (UI rule U2)")
        XCTAssertEqual(LiveModeRevealHandlePolicy.idleDimDelay, 3)
        XCTAssertEqual(LiveModeRevealHandlePolicy.dimmedOpacity, 0.3)
        XCTAssertEqual(LiveModeRevealHandlePolicy.fullOpacity, 0.9)
        XCTAssertGreaterThan(LiveModeRevealHandlePolicy.dimmedOpacity, 0, "the handle must never be fully invisible")
    }
}
