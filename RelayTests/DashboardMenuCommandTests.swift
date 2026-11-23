import XCTest
import CoreGraphics
import Combine
@testable import Relay

final class DashboardMenuCommandTests: XCTestCase {

    // MARK: - Titles

    func testDeleteSelectionTitleFollowsViewMode() {
        XCTAssertEqual(DashboardMenuTitles.deleteSelection(isAutomation: false), "Delete Selected Tiles")
        XCTAssertEqual(DashboardMenuTitles.deleteSelection(isAutomation: true), "Delete Selected Nodes")
    }

    func testPanelToggleTitles() {
        XCTAssertEqual(DashboardMenuTitles.tileOverviewToggle(isVisible: false), "Show Tile Overview")
        XCTAssertEqual(DashboardMenuTitles.tileOverviewToggle(isVisible: true), "Hide Tile Overview")
        XCTAssertEqual(DashboardMenuTitles.inspectorToggle(isVisible: false), "Show Inspector")
        XCTAssertEqual(DashboardMenuTitles.inspectorToggle(isVisible: true), "Hide Inspector")
    }

    func testCountAwareTileTitles() {
        XCTAssertEqual(DashboardMenuTitles.editTiles(count: 1), "Edit Tile…")
        XCTAssertEqual(DashboardMenuTitles.editTiles(count: 3), "Edit 3 Tiles…")
        XCTAssertEqual(DashboardMenuTitles.deleteTiles(count: 1), "Delete Tile")
        XCTAssertEqual(DashboardMenuTitles.deleteTiles(count: 3), "Delete 3 Tiles")
        XCTAssertEqual(DashboardMenuTitles.duplicateTiles(count: 1), "Duplicate Tile")
        XCTAssertEqual(DashboardMenuTitles.duplicateTiles(count: 2), "Duplicate 2 Tiles")
        XCTAssertEqual(DashboardMenuTitles.groupTiles(count: 3), "Group 3 Tiles…")
    }

    func testTargetCountIsTheSelectionOnlyWhenTheTileIsInIt() {
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(DashboardMenuTitles.targetTileCount(tileID: a, selectedTileIDs: [a, b, c]), 3)
        // Right-clicking a tile outside the selection acts on that tile alone.
        XCTAssertEqual(DashboardMenuTitles.targetTileCount(tileID: a, selectedTileIDs: [b, c]), 1)
        XCTAssertEqual(DashboardMenuTitles.targetTileCount(tileID: a, selectedTileIDs: []), 1)
    }

    // MARK: - Menu state

    func testMenuStatePublishesOnlyOnChange() {
        let state = DashboardMenuState()
        var sends = 0
        let token = state.objectWillChange.sink { sends += 1 }
        defer { token.cancel() }

        var snapshot = DashboardMenuSnapshot()
        state.update(snapshot)
        XCTAssertEqual(sends, 0)

        snapshot.selectedTileCount = 2
        state.update(snapshot)
        XCTAssertEqual(sends, 1)
        XCTAssertEqual(state.snapshot.selectedTileCount, 2)

        state.update(snapshot)
        XCTAssertEqual(sends, 1)
    }

    // MARK: - Zoom commands

    func testZoomInStepsAboutTheViewportCentre() {
        let viewport = CGSize(width: 800, height: 600)
        let result = ViewportZoomCommand.zoomIn.applied(
            zoom: 1, pan: .zero, contentSize: CGSize(width: 1920, height: 1080),
            viewportSize: viewport, range: 0.25...3
        )!
        XCTAssertEqual(result.zoom, 1.12, accuracy: 1e-9)
        // The canvas point under the centre stays under the centre.
        let centre = CGPoint(x: 400, y: 300)
        let before = CGPoint(x: centre.x / 1, y: centre.y / 1)
        let after = CGPoint(x: (centre.x - result.pan.width) / result.zoom, y: (centre.y - result.pan.height) / result.zoom)
        XCTAssertEqual(before.x, after.x, accuracy: 1e-9)
        XCTAssertEqual(before.y, after.y, accuracy: 1e-9)
    }

    func testZoomOutClampsAndStopsAtTheLimit() {
        let viewport = CGSize(width: 800, height: 600)
        let clamped = ViewportZoomCommand.zoomOut.applied(
            zoom: 0.3, pan: .zero, contentSize: .zero, viewportSize: viewport, range: 0.25...3
        )!
        XCTAssertEqual(clamped.zoom, 0.25, accuracy: 1e-9)

        XCTAssertNil(ViewportZoomCommand.zoomOut.applied(
            zoom: 0.25, pan: .zero, contentSize: .zero, viewportSize: viewport, range: 0.25...3
        ))
        XCTAssertNil(ViewportZoomCommand.zoomIn.applied(
            zoom: 3, pan: .zero, contentSize: .zero, viewportSize: viewport, range: 0.25...3
        ))
    }

    func testActualSizeCentresTheContentAt100Percent() {
        let result = ViewportZoomCommand.actualSize.applied(
            zoom: 0.5, pan: CGSize(width: 12, height: 34),
            contentSize: CGSize(width: 1000, height: 500),
            viewportSize: CGSize(width: 800, height: 600), range: 0.25...3
        )!
        XCTAssertEqual(result.zoom, 1)
        XCTAssertEqual(result.pan, CGSize(width: -100, height: 50))
    }

    func testActualSizeBeforeLayoutResetsPan() {
        let result = ViewportPanZoomControls.actualSizeViewport(contentSize: CGSize(width: 100, height: 100), viewportSize: .zero)
        XCTAssertEqual(result.zoom, 1)
        XCTAssertEqual(result.pan, .zero)
    }

    // MARK: - Arrange operations

    private func tile(x: CGFloat, y: CGFloat, w: CGFloat = 200, h: CGFloat = 200, hidden: Bool = false) -> DashboardTileModel {
        var t = DashboardTileModel(id: UUID(), kind: .empty, offset: CGSize(width: x, height: y), size: CGSize(width: w, height: h))
        t.isHidden = hidden
        return t
    }

    func testAlignToGridMovesOnlySelectedTiles() {
        let a = tile(x: 13, y: 27)
        let b = tile(x: 31, y: 9)
        let result = DashboardTileArrangeOperations.alignedToGrid([a, b], selectedIDs: [a.id], gridSize: 20)!
        XCTAssertEqual(result[0].offset, CGSize(width: 20, height: 20))
        XCTAssertEqual(result[1].offset, b.offset)
    }

    func testAlignToGridNeedsAPositiveGrid() {
        XCTAssertNil(DashboardTileArrangeOperations.alignedToGrid([tile(x: 1, y: 1)], selectedIDs: [], gridSize: 0))
    }

    func testResolveOverlapsSeparatesOverlappingTiles() {
        let a = tile(x: 0, y: 0)
        let b = tile(x: 40, y: 40)
        let resolved = DashboardTileArrangeOperations.overlapsResolved(
            [a, b], selectedIDs: [], gridSize: 20,
            canvasSize: CGSize(width: 1000, height: 1000), defaultTileSize: CGSize(width: 260, height: 200)
        )!
        XCTAssertTrue(resolved.didChange)
        let rects = resolved.tiles.map { CGRect(origin: CGPoint(x: $0.offset.width, y: $0.offset.height), size: $0.size!) }
        XCTAssertFalse(rects[0].intersects(rects[1]))
        // Everything stays on the grid and inside the canvas.
        for r in rects {
            XCTAssertEqual(r.minX.truncatingRemainder(dividingBy: 20), 0)
            XCTAssertEqual(r.minY.truncatingRemainder(dividingBy: 20), 0)
            XCTAssertTrue(CGRect(x: 0, y: 0, width: 1000, height: 1000).contains(r))
        }
    }

    func testResolveOverlapsLeavesUnselectedAndHiddenTilesAlone() {
        let a = tile(x: 0, y: 0)
        let b = tile(x: 40, y: 40)
        let hidden = tile(x: 60, y: 60, hidden: true)
        let resolved = DashboardTileArrangeOperations.overlapsResolved(
            [a, b, hidden], selectedIDs: [b.id], gridSize: 20,
            canvasSize: CGSize(width: 1000, height: 1000), defaultTileSize: CGSize(width: 260, height: 200)
        )!
        XCTAssertEqual(resolved.tiles[0].offset, a.offset)
        XCTAssertNotEqual(resolved.tiles[1].offset, b.offset)
        XCTAssertEqual(resolved.tiles[2].offset, hidden.offset)
    }

    func testResolveOverlapsReportsNoChangeWhenNothingOverlaps() {
        let a = tile(x: 0, y: 0)
        let b = tile(x: 400, y: 400)
        let resolved = DashboardTileArrangeOperations.overlapsResolved(
            [a, b], selectedIDs: [], gridSize: 20,
            canvasSize: CGSize(width: 1000, height: 1000), defaultTileSize: CGSize(width: 260, height: 200)
        )!
        XCTAssertFalse(resolved.didChange)
    }

    func testResolveOverlapsNeedsVisibleTiles() {
        XCTAssertNil(DashboardTileArrangeOperations.overlapsResolved(
            [tile(x: 0, y: 0, hidden: true)], selectedIDs: [], gridSize: 20,
            canvasSize: CGSize(width: 1000, height: 1000), defaultTileSize: .zero
        ))
    }
}
