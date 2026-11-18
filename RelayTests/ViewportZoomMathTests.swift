import XCTest
import CoreGraphics
@testable import Relay

final class ViewportZoomMathTests: XCTestCase {

    func testAnchoredZoomKeepsAnchorFixed() {
        let r = ViewportZoomMath.anchoredZoom(
            currentZoom: 1, currentPan: CGSize(width: 10, height: 20),
            proposedZoom: 2, anchorInView: CGPoint(x: 100, y: 50), range: 0.25...3
        )!
        XCTAssertEqual(r.zoom, 2, accuracy: 1e-9)
        XCTAssertEqual(r.pan.width, -80, accuracy: 1e-9)   // 10*2 + (1-2)*100
        XCTAssertEqual(r.pan.height, -10, accuracy: 1e-9)  // 20*2 + (1-2)*50
    }

    func testAnchoredZoomClampsToRange() {
        let r = ViewportZoomMath.anchoredZoom(
            currentZoom: 2.5, currentPan: .zero,
            proposedZoom: 9, anchorInView: .zero, range: 0.25...3
        )!
        XCTAssertEqual(r.zoom, 3, accuracy: 1e-9)
    }

    func testAnchoredZoomAtLimitReturnsNil() {
        XCTAssertNil(ViewportZoomMath.anchoredZoom(
            currentZoom: 3, currentPan: CGSize(width: 5, height: 5),
            proposedZoom: 3.4, anchorInView: CGPoint(x: 40, y: 40), range: 0.25...3
        ))
    }

    func testAnchoredZoomRejectsNonPositiveCurrentZoom() {
        XCTAssertNil(ViewportZoomMath.anchoredZoom(
            currentZoom: 0, currentPan: .zero,
            proposedZoom: 1, anchorInView: .zero, range: 0.25...3
        ))
    }

    func testScrollZoomFactor() {
        XCTAssertEqual(ViewportZoomMath.scrollZoomFactor(deltaY: -100), 1.1, accuracy: 1e-9)
    }

    func testModifiedScrollIsZoom() {
        XCTAssertEqual(ViewportZoomMath.scrollIntent(option: true, command: false, control: false), .zoom)
        XCTAssertEqual(ViewportZoomMath.scrollIntent(option: false, command: true, control: false), .zoom)
        XCTAssertEqual(ViewportZoomMath.scrollIntent(option: false, command: false, control: true), .zoom)
    }

    func testShiftScrollIsPan() {
        // Shift is not one of the zoom modifiers, so Shift+scroll stays a (horizontal) pan.
        XCTAssertEqual(ViewportZoomMath.scrollIntent(option: false, command: false, control: false), .pan)
    }

    private let frame = CGRect(x: 0, y: 0, width: 100, height: 100)

    func testWindowlessEventAcceptedOverCanvasWhenDashboardTopmost() {
        XCTAssertTrue(ViewportZoomMath.acceptsWindowlessEvent(
            screenPoint: CGPoint(x: 50, y: 50), viewFrameOnScreen: frame,
            isAppActive: true, isViewWindowTopmostUnderCursor: true
        ))
    }

    func testWindowlessEventAcceptedWhenAnotherRelayWindowIsKeyButNotUnderCursor() {
        // e.g. the Variables window was clicked last, but the fingers are on the dashboard.
        // Key-ness isn't an input: only "app active" and "our window is under the cursor" are.
        XCTAssertTrue(ViewportZoomMath.acceptsWindowlessEvent(
            screenPoint: CGPoint(x: 50, y: 50), viewFrameOnScreen: frame,
            isAppActive: true, isViewWindowTopmostUnderCursor: true
        ))
    }

    func testWindowlessEventRejectedOutsideView() {
        XCTAssertFalse(ViewportZoomMath.acceptsWindowlessEvent(
            screenPoint: CGPoint(x: 150, y: 50), viewFrameOnScreen: frame,
            isAppActive: true, isViewWindowTopmostUnderCursor: true
        ))
    }

    func testWindowlessEventRejectedOverWindowAboveCanvas() {
        // A floating Relay window (Variables), a sheet (Settings) or another app's window
        // sits above the canvas under the cursor.
        XCTAssertFalse(ViewportZoomMath.acceptsWindowlessEvent(
            screenPoint: CGPoint(x: 50, y: 50), viewFrameOnScreen: frame,
            isAppActive: true, isViewWindowTopmostUnderCursor: false
        ))
    }

    func testWindowlessEventRejectedWhenAppInactive() {
        XCTAssertFalse(ViewportZoomMath.acceptsWindowlessEvent(
            screenPoint: CGPoint(x: 50, y: 50), viewFrameOnScreen: frame,
            isAppActive: false, isViewWindowTopmostUnderCursor: true
        ))
    }
}
