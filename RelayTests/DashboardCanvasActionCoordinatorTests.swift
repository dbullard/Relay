import XCTest
@testable import Relay

@MainActor
final class DashboardCanvasActionCoordinatorTests: XCTestCase {

    func testCallingBeforeConfigurationIsANoOp() {
        // A coordinator that hasn't had its closures assigned yet (e.g. the
        // first frame before DashboardRootView.body has run once) must not
        // crash -- every call site should be a safe no-op.
        let coordinator = DashboardCanvasActionCoordinator()
        coordinator.delete(tileID: UUID())
        coordinator.persist(reconcileGraphNodes: false)
        coordinator.primarySelect(tileID: UUID())
        // No assertion needed -- this test passes by not crashing.
    }

    func testForwardsDeleteToTheCurrentlyAssignedClosure() {
        let coordinator = DashboardCanvasActionCoordinator()
        var deletedIDs: [UUID] = []
        coordinator.onDelete = { tileID in deletedIDs.append(tileID) }

        let id = UUID()
        coordinator.delete(tileID: id)

        XCTAssertEqual(deletedIDs, [id])
    }

    func testReassigningAClosureReplacesTheOldOneEntirely() {
        let coordinator = DashboardCanvasActionCoordinator()
        var firstCallCount = 0
        var secondCallCount = 0

        coordinator.onDelete = { _ in firstCallCount += 1 }
        coordinator.delete(tileID: UUID())

        coordinator.onDelete = { _ in secondCallCount += 1 }
        coordinator.delete(tileID: UUID())

        // Simulates what DashboardRootView does every render: reassign the
        // closure. Only the latest assignment should ever fire.
        XCTAssertEqual(firstCallCount, 1)
        XCTAssertEqual(secondCallCount, 1)
    }

    func testSetTileForwardsToTheCurrentlyAssignedClosure() {
        let coordinator = DashboardCanvasActionCoordinator()
        var received: (UUID, UUID, DashboardTileModel)?
        coordinator.onSetTile = { tabID, tileID, tile in received = (tabID, tileID, tile) }

        let tabID = UUID()
        let tileID = UUID()
        let tile = DashboardTileModel.previewDefault
        coordinator.setTile(tabID: tabID, tileID: tileID, to: tile)

        XCTAssertEqual(received?.0, tabID)
        XCTAssertEqual(received?.1, tileID)
        XCTAssertEqual(received?.2, tile)
    }
}

private extension DashboardTileModel {
    // Minimal test fixture: only the initializer's non-defaulted parameters
    // (kind, offset) plus id and size are supplied explicitly; every other
    // field uses its production default.
    static var previewDefault: DashboardTileModel {
        DashboardTileModel(id: UUID(), kind: .empty, offset: .zero, size: CGSize(width: 200, height: 150))
    }
}
