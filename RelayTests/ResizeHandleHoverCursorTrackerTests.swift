import XCTest
@testable import Relay

final class ResizeHandleHoverCursorTrackerTests: XCTestCase {
    func testNoHandleToNoHandleReturnsNone() {
        var tracker = ResizeHandleHoverCursorTracker()
        XCTAssertEqual(tracker.update(to: nil), .none)
    }

    func testEnteringHandleFromNoneReturnsPush() {
        var tracker = ResizeHandleHoverCursorTracker()
        XCTAssertEqual(tracker.update(to: .horizontalLeft), .push(.horizontalLeft))
    }

    func testStayingOnSameHandleReturnsNone() {
        var tracker = ResizeHandleHoverCursorTracker()
        _ = tracker.update(to: .horizontalLeft)
        XCTAssertEqual(tracker.update(to: .horizontalLeft), .none)
    }

    func testSwitchingHandlesReturnsPopThenPush() {
        var tracker = ResizeHandleHoverCursorTracker()
        _ = tracker.update(to: .horizontalLeft)
        XCTAssertEqual(tracker.update(to: .diagonalTopLeft), .popThenPush(.diagonalTopLeft))
    }

    func testLeavingHandleReturnsPop() {
        var tracker = ResizeHandleHoverCursorTracker()
        _ = tracker.update(to: .horizontal)
        XCTAssertEqual(tracker.update(to: nil), .pop)
    }

    func testLeavingWithNoPriorHandleReturnsNoneNotPop() {
        // Guards against an unbalanced NSCursor.pop() when the mouse moves
        // across the tile interior without ever having entered a handle.
        var tracker = ResizeHandleHoverCursorTracker()
        XCTAssertEqual(tracker.update(to: nil), .none)
        XCTAssertEqual(tracker.update(to: nil), .none)
    }
}
