import XCTest
@testable import Relay

@MainActor
final class DashboardTileResizeHandleLayoutTests: XCTestCase {
    func testClosestHandleReturnsNilOutsideRadius() {
        let layout = DashboardTileResizeHandleLayout(size: CGSize(width: 200, height: 100))

        // Center of the tile is far from every handle.
        let center = CGPoint(x: 100, y: 50)
        XCTAssertNil(layout.closestHandle(to: center))
    }

    func testClosestHandleReturnsBottomRightCorner() {
        let layout = DashboardTileResizeHandleLayout(size: CGSize(width: 200, height: 100))

        let nearBottomRight = CGPoint(x: layout.bottomRight.x + 2, y: layout.bottomRight.y + 1)
        let hit = layout.closestHandle(to: nearBottomRight)

        XCTAssertEqual(hit?.orientation, .diagonal)
    }

    func testClosestHandlePicksNearestWhenTwoAreInRange() {
        let layout = DashboardTileResizeHandleLayout(size: CGSize(width: 200, height: 100))

        // A point exactly between bottomRight (.diagonal) and rightEdge (.horizontal),
        // but closer to bottomRight.
        let midpoint = CGPoint(
            x: (layout.bottomRight.x + layout.rightEdge.x) / 2,
            y: layout.bottomRight.y - 1
        )
        let hit = layout.closestHandle(to: midpoint)

        XCTAssertEqual(hit?.orientation, .diagonal)
    }

    func testClosestHandleRespectsAllowedOrientations() {
        let layout = DashboardTileResizeHandleLayout(size: CGSize(width: 200, height: 100))

        let nearBottomRight = CGPoint(x: layout.bottomRight.x + 2, y: layout.bottomRight.y + 1)
        let hit = layout.closestHandle(
            to: nearBottomRight,
            allowedOrientations: [.vertical, .verticalTop]
        )

        // .diagonal is excluded, so no allowed handle is close enough.
        XCTAssertNil(hit)
    }

    func testClosestHandleAllowsRestrictedOrientationWhenInRange() {
        let layout = DashboardTileResizeHandleLayout(size: CGSize(width: 200, height: 100))

        let nearBottomEdge = CGPoint(x: layout.bottomEdge.x, y: layout.bottomEdge.y)
        let hit = layout.closestHandle(
            to: nearBottomEdge,
            allowedOrientations: [.vertical, .verticalTop]
        )

        XCTAssertEqual(hit?.orientation, .vertical)
    }
}
