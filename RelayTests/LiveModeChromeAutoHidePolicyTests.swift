import XCTest
@testable import Relay

final class LiveModeChromeAutoHidePolicyTests: XCTestCase {

    func testPassiveHoverDoesNotDismissChrome() {
        XCTAssertFalse(
            LiveModeChromeAutoHidePolicy.shouldHide(
                isHovering: true,
                isInteracting: false,
                respectsHover: true
            )
        )
    }

    func testCompletedInteractionDismissesEvenWhenStillHovered() {
        XCTAssertTrue(
            LiveModeChromeAutoHidePolicy.shouldHide(
                isHovering: true,
                isInteracting: false,
                respectsHover: false
            )
        )
    }

    func testActiveInteractionDoesNotDismissChrome() {
        XCTAssertFalse(
            LiveModeChromeAutoHidePolicy.shouldHide(
                isHovering: false,
                isInteracting: true,
                respectsHover: false
            )
        )
    }

    func testHoverPausesPassiveHoverHideTimer() {
        XCTAssertTrue(
            LiveModeChromeAutoHidePolicy.shouldPauseScheduledHideForHover(respectsHover: true)
        )
    }

    func testHoverDoesNotPauseTouchOrInteractionHideTimer() {
        XCTAssertFalse(
            LiveModeChromeAutoHidePolicy.shouldPauseScheduledHideForHover(respectsHover: false)
        )
    }
}
