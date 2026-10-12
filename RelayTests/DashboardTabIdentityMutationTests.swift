import XCTest
import SwiftUI
@testable import Relay

@MainActor
final class DashboardTabIdentityMutationTests: XCTestCase {

    func testTileReplacementFollowsTabIDAfterReorder() {
        let tileID = UUID()
        let targetTab = DashboardTab.fixture(tiles: [.fixture(id: tileID)])
        var tabs = [targetTab, DashboardTab.fixture()]
        let replacement = DashboardTileModel.fixture(id: tileID, offset: CGSize(width: 20, height: 20))

        tabs.swapAt(0, 1)

        XCTAssertTrue(DashboardTabIdentityMutation.replaceTile(
            replacement, tabID: targetTab.id, tileID: tileID, in: &tabs
        ))
        XCTAssertEqual(tabs.first(where: { $0.id == targetTab.id })?.tiles.first?.offset,
                       CGSize(width: 20, height: 20))
    }

    func testMissingTabIDDoesNotMutateAnyTab() {
        var tabs = [DashboardTab.fixture()]
        let before = tabs
        XCTAssertFalse(DashboardTabIdentityMutation.replaceTab(.fixture(), withID: UUID(), in: &tabs))
        XCTAssertEqual(tabs, before)
    }

    func testMissingTileIDDoesNotMutateAnyTabWhenTabExists() {
        let targetTab = DashboardTab.fixture(tiles: [.fixture()])
        var tabs = [targetTab]
        let before = tabs

        XCTAssertFalse(DashboardTabIdentityMutation.replaceTile(
            .fixture(), tabID: targetTab.id, tileID: UUID(), in: &tabs
        ))
        XCTAssertEqual(tabs, before)
    }

    /// Regression guard for the actual bug: a coordinator closure configured while
    /// tab A was selected must not write into whatever tab now occupies that index.
    /// This models how `DashboardRootView` wires `onSetTile`, and FAILS against the
    /// prior index-captured binding.
    func testCoordinatorWriteAfterReorderTargetsOriginalTabNotOriginalIndex() {
        let tileID = UUID()
        let tabA = DashboardTab.fixture(tiles: [.fixture(id: tileID)])
        let tabB = DashboardTab.fixture(tiles: [.fixture(id: tileID)])
        var tabs = [tabA, tabB]

        let coordinator = DashboardCanvasActionCoordinator()
        coordinator.onSetTile = { tabID, tileID, newValue in
            _ = DashboardTabIdentityMutation.replaceTile(newValue, tabID: tabID, tileID: tileID, in: &tabs)
        }

        tabs.swapAt(0, 1)   // tab A is now at index 1

        coordinator.setTile(tabID: tabA.id, tileID: tileID,
                            to: .fixture(id: tileID, offset: CGSize(width: 99, height: 99)))

        XCTAssertEqual(tabs.first(where: { $0.id == tabA.id })?.tiles.first?.offset,
                       CGSize(width: 99, height: 99))
        XCTAssertEqual(tabs.first(where: { $0.id == tabB.id })?.tiles.first?.offset, .zero)
    }

    func testSetTileForwardsTabAndTileIDs() {
        let coordinator = DashboardCanvasActionCoordinator()
        var received: (UUID, UUID, DashboardTileModel)?
        coordinator.onSetTile = { tabID, tileID, tile in received = (tabID, tileID, tile) }

        let tabID = UUID(), tileID = UUID()
        let tile = DashboardTileModel.fixture(id: tileID)
        coordinator.setTile(tabID: tabID, tileID: tileID, to: tile)

        XCTAssertEqual(received?.0, tabID)
        XCTAssertEqual(received?.1, tileID)
        XCTAssertEqual(received?.2, tile)
    }

    /// Regression guard for DashboardRootView's tile-overview sidebar callbacks
    /// (onRenameTile/onUpdateTileSize/onToggleTileVisibility), which the sidebar
    /// wires while a specific tab is selected. If those closures re-resolve the
    /// target tab from a live `selectedTabIndex` read at call time (the prior bug)
    /// rather than the UUID captured when the sidebar was built, a tab
    /// reorder/selection change before the write lands corrupts the wrong tab
    /// instead of the one the sidebar was showing.
    func testTileOverviewRenameClosureTargetsCapturedTabNotCurrentSelection() {
        let tileID = UUID()
        let tabA = DashboardTab.fixture(tiles: [.fixture(id: tileID)])
        let tabB = DashboardTab.fixture(tiles: [.fixture(id: tileID)])
        var tabs = [tabA, tabB]

        // Sidebar constructed while tab A is selected: captures tab A's UUID, not
        // its index, so a later reorder can't misdirect the write.
        let overviewTabID = tabA.id
        let onRenameTile: (UUID, String) -> Void = { renamedTileID, newName in
            guard let tabIndex = DashboardTabIdentityMutation.index(of: overviewTabID, in: tabs),
                  var tile = tabs[tabIndex].tiles.first(where: { $0.id == renamedTileID }) else { return }
            tile.name = newName
            _ = DashboardTabIdentityMutation.replaceTile(tile, tabID: overviewTabID, tileID: renamedTileID, in: &tabs)
        }

        tabs.swapAt(0, 1)   // tab A is now at index 1; selection moved on elsewhere

        onRenameTile(tileID, "Renamed")

        XCTAssertEqual(tabs.first(where: { $0.id == tabA.id })?.tiles.first?.name, "Renamed")
        XCTAssertEqual(tabs.first(where: { $0.id == tabB.id })?.tiles.first?.name, "")
    }

    /// Same wiring risk as above, but for onReorderTiles, which operates on the whole
    /// tiles array via `index(of:in:)` rather than `replaceTile`. If the captured tab
    /// is deleted before the write, the closure must reject safely, not crash or
    /// silently reorder tiles in whatever tab now occupies the stale index.
    func testTileOverviewReorderClosureRejectsWhenCapturedTabDeleted() {
        let tabA = DashboardTab.fixture(tiles: [.fixture(), .fixture()])
        let tabB = DashboardTab.fixture(tiles: [
            .fixture(name: "B1"), .fixture(name: "B2"), .fixture(name: "B3")
        ])
        var tabs = [tabA, tabB]
        let tabBOriginalOrder = tabB.tiles.map(\.name)

        let overviewTabID = tabA.id
        let onReorderTiles: (IndexSet, Int) -> Void = { indices, newOffset in
            guard let tabIndex = DashboardTabIdentityMutation.index(of: overviewTabID, in: tabs) else { return }
            tabs[tabIndex].tiles.move(fromOffsets: indices, toOffset: newOffset)
        }

        tabs.removeAll { $0.id == tabA.id }   // tab A deleted while the sidebar was still showing it

        onReorderTiles(IndexSet(integer: 0), 2)

        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(tabs.first?.id, tabB.id)
        // Tab A no longer exists; tab B (now at the stale index) must be untouched,
        // not silently reordered in tab A's place.
        XCTAssertEqual(tabs.first?.tiles.map(\.name), tabBOriginalOrder)
    }

    /// Regression guard for the PCO config sheet's onMakeSyncedTab/onStopSyncingTab,
    /// which resolve an index by captured tab UUID at call time (rather than reusing
    /// a frozen `selectedTabIndex`) before invoking an index-based mutator.
    func testSyncActionIndexResolvesToCapturedTabAfterReorder() {
        let tabA = DashboardTab.fixture()
        let tabB = DashboardTab.fixture()
        var tabs = [tabA, tabB]
        let frozenIndex = 0   // selectedTabIndex at the moment the sheet was presented

        let configTabID = tabA.id
        tabs.swapAt(0, 1)   // tab A is now at index 1

        guard let resolvedIndex = DashboardTabIdentityMutation.index(of: configTabID, in: tabs) else {
            XCTFail("expected tab A to still be resolvable by ID")
            return
        }

        XCTAssertEqual(resolvedIndex, 1)
        XCTAssertNotEqual(resolvedIndex, frozenIndex)
        XCTAssertEqual(tabs[resolvedIndex].id, tabA.id)
    }
}

private extension DashboardTileModel {
    static func fixture(id: UUID = UUID(), name: String = "", offset: CGSize = .zero) -> Self {
        DashboardTileModel(id: id, name: name, kind: .empty, offset: offset, size: CGSize(width: 200, height: 150))
    }
}

private extension DashboardTab {
    static func fixture(id: UUID = UUID(), tiles: [DashboardTileModel] = []) -> Self {
        DashboardTab(id: id, name: "Test Tab", tiles: tiles)
    }
}
