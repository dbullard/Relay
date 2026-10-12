import XCTest
@testable import Relay

@MainActor
final class DashboardTileInteractionSessionTests: XCTestCase {
    func testInitialState() {
        let session = DashboardTileInteractionSession()

        XCTAssertEqual(session.groupDragDelta, .zero)
        XCTAssertTrue(session.groupDragFollowerIDs.isEmpty)
        XCTAssertEqual(session.groupResizeHeightDelta, 0)
        XCTAssertEqual(session.groupResizeOffsetYDelta, 0)
        XCTAssertTrue(session.groupResizeFollowerIDs.isEmpty)
        XCTAssertTrue(session.activeSmartGuides.isEmpty)
        XCTAssertNil(session.draggedTileID)
        XCTAssertEqual(session.draggedTileDelta, .zero)
        XCTAssertNil(session.activeSnapRegion)
        XCTAssertTrue(session.activeSnapTileFrames.isEmpty)
    }

    /// Guards against a future field being added to the class but not to
    /// `reset()` -- every stored property is set to a non-default value
    /// first, `reset()` is called once, and every property is asserted back
    /// to its zero/empty/nil default. If a new `@Observable` property is
    /// added to the session without also being cleared in `reset()`, this
    /// test should be extended (and would otherwise fail to catch the gap
    /// silently) -- it exists specifically so that omission is visible.
    func testResetClearsAllFields() {
        let session = DashboardTileInteractionSession()

        session.groupDragDelta = CGSize(width: 12, height: -8)
        session.groupDragFollowerIDs = [UUID(), UUID()]
        session.groupResizeHeightDelta = 40
        session.groupResizeOffsetYDelta = -15
        session.groupResizeFollowerIDs = [UUID()]
        session.activeSmartGuides = [
            SmartGuideLine(orientation: .vertical, position: 100),
            SmartGuideLine(orientation: .horizontal, position: 50)
        ]
        session.draggedTileID = UUID()
        session.draggedTileDelta = CGSize(width: 5, height: 5)
        session.activeSnapRegion = .halfLeft
        session.activeSnapTileFrames = [UUID(): CGRect(x: 0, y: 0, width: 100, height: 100)]

        session.reset()

        XCTAssertEqual(session.groupDragDelta, .zero)
        XCTAssertTrue(session.groupDragFollowerIDs.isEmpty)
        XCTAssertEqual(session.groupResizeHeightDelta, 0)
        XCTAssertEqual(session.groupResizeOffsetYDelta, 0)
        XCTAssertTrue(session.groupResizeFollowerIDs.isEmpty)
        XCTAssertTrue(session.activeSmartGuides.isEmpty)
        XCTAssertNil(session.draggedTileID)
        XCTAssertEqual(session.draggedTileDelta, .zero)
        XCTAssertNil(session.activeSnapRegion)
        XCTAssertTrue(session.activeSnapTileFrames.isEmpty)
    }
}
