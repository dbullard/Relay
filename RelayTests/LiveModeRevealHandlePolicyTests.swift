import XCTest
import CoreGraphics
@testable import Relay

final class LiveModeRevealHandlePolicyTests: XCTestCase {

    func testShownWhileChromeHidden() {
        XCTAssertTrue(LiveModeRevealHandlePolicy.isShown(isChromeVisible: false, isHandleDragging: false))
    }

    func testHiddenWhileChromeShowsAndHandleIdle() {
        XCTAssertFalse(LiveModeRevealHandlePolicy.isShown(isChromeVisible: true, isHandleDragging: false))
    }

    func testStaysShownWhileItsOwnDragRevealsChrome() {
        // The reveal drag makes the chrome visible on its first change; the handle must stay
        // (and keep its gesture) or SwiftUI cancels the drag and onEnded never runs.
        XCTAssertTrue(LiveModeRevealHandlePolicy.isShown(isChromeVisible: true, isHandleDragging: true))
    }

    func testFingerJitterCountsAsTap() {
        XCTAssertTrue(LiveModeRevealHandlePolicy.isTap(translation: CGSize(width: 2, height: 3)))
        XCTAssertTrue(LiveModeRevealHandlePolicy.isTap(translation: CGSize(width: -4, height: -2)))
    }

    func testRealDragIsNotTap() {
        XCTAssertFalse(LiveModeRevealHandlePolicy.isTap(translation: CGSize(width: 0, height: 8)))
        XCTAssertFalse(LiveModeRevealHandlePolicy.isTap(translation: CGSize(width: 7, height: 0)))
    }

    func testSpecValues() {
        XCTAssertEqual(LiveModeRevealHandlePolicy.hotZoneHeight, 28)
        XCTAssertEqual(LiveModeRevealHandlePolicy.pillSize, CGSize(width: 44, height: 6))
        XCTAssertEqual(LiveModeRevealHandlePolicy.tapTargetSize, CGSize(width: 60, height: 44), "44 pt minimum touch target (UI rule U2)")
        XCTAssertEqual(LiveModeRevealHandlePolicy.idleDimDelay, 3)
        XCTAssertEqual(LiveModeRevealHandlePolicy.dimmedOpacity, 0.3)
        XCTAssertEqual(LiveModeRevealHandlePolicy.fullOpacity, 0.9)
        XCTAssertEqual(LiveModeRevealHandlePolicy.tapSlop, 6)
        XCTAssertGreaterThan(LiveModeRevealHandlePolicy.dimmedOpacity, 0, "the handle must never be fully invisible")
    }
}
