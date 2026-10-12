import XCTest
@testable import Relay

final class DashboardTileArrangementTests: XCTestCase {

    // MARK: - CanvasFractionRegion

    func testFractionRegionRects() {
        let canvasSize = CGSize(width: 1200, height: 800)

        XCTAssertEqual(CanvasFractionRegion.halfLeft.rect(in: canvasSize), CGRect(x: 0, y: 0, width: 600, height: 800))
        XCTAssertEqual(CanvasFractionRegion.halfRight.rect(in: canvasSize), CGRect(x: 600, y: 0, width: 600, height: 800))
        XCTAssertEqual(CanvasFractionRegion.halfTop.rect(in: canvasSize), CGRect(x: 0, y: 0, width: 1200, height: 400))
        XCTAssertEqual(CanvasFractionRegion.halfBottom.rect(in: canvasSize), CGRect(x: 0, y: 400, width: 1200, height: 400))

        XCTAssertEqual(CanvasFractionRegion.thirdLeft.rect(in: canvasSize), CGRect(x: 0, y: 0, width: 400, height: 800))
        XCTAssertEqual(CanvasFractionRegion.thirdCenter.rect(in: canvasSize), CGRect(x: 400, y: 0, width: 400, height: 800))
        XCTAssertEqual(CanvasFractionRegion.thirdRight.rect(in: canvasSize), CGRect(x: 800, y: 0, width: 400, height: 800))

        XCTAssertEqual(CanvasFractionRegion.fourthColumn1.rect(in: canvasSize), CGRect(x: 0, y: 0, width: 300, height: 800))
        XCTAssertEqual(CanvasFractionRegion.fourthColumn2.rect(in: canvasSize), CGRect(x: 300, y: 0, width: 300, height: 800))
        XCTAssertEqual(CanvasFractionRegion.fourthColumn3.rect(in: canvasSize), CGRect(x: 600, y: 0, width: 300, height: 800))
        XCTAssertEqual(CanvasFractionRegion.fourthColumn4.rect(in: canvasSize), CGRect(x: 900, y: 0, width: 300, height: 800))

        XCTAssertEqual(CanvasFractionRegion.quarterTopLeft.rect(in: canvasSize), CGRect(x: 0, y: 0, width: 600, height: 400))
        XCTAssertEqual(CanvasFractionRegion.quarterTopRight.rect(in: canvasSize), CGRect(x: 600, y: 0, width: 600, height: 400))
        XCTAssertEqual(CanvasFractionRegion.quarterBottomLeft.rect(in: canvasSize), CGRect(x: 0, y: 400, width: 600, height: 400))
        XCTAssertEqual(CanvasFractionRegion.quarterBottomRight.rect(in: canvasSize), CGRect(x: 600, y: 400, width: 600, height: 400))
        XCTAssertEqual(CanvasFractionRegion.full.rect(in: canvasSize), CGRect(x: 0, y: 0, width: 1200, height: 800))
    }

    func testFractionRegionSections() {
        XCTAssertEqual(CanvasFractionRegion.halfLeft.section, "Half")
        XCTAssertEqual(CanvasFractionRegion.thirdCenter.section, "Thirds")
        XCTAssertEqual(CanvasFractionRegion.fourthColumn3.section, "Fourths")
        XCTAssertEqual(CanvasFractionRegion.quarterBottomRight.section, "Quarters")
        XCTAssertEqual(CanvasFractionRegion.full.section, "Full")
    }

    // MARK: - CanvasFractionRegion.proximityRegion

    func testProximityRegionResolvesAllFourCorners() {
        let canvasSize = CGSize(width: 1200, height: 800)
        let threshold: CGFloat = 50

        XCTAssertEqual(
            CanvasFractionRegion.proximityRegion(at: CGPoint(x: 10, y: 10), canvasSize: canvasSize, edgeThreshold: threshold),
            .quarterTopLeft
        )
        XCTAssertEqual(
            CanvasFractionRegion.proximityRegion(at: CGPoint(x: 1190, y: 10), canvasSize: canvasSize, edgeThreshold: threshold),
            .quarterTopRight
        )
        XCTAssertEqual(
            CanvasFractionRegion.proximityRegion(at: CGPoint(x: 10, y: 790), canvasSize: canvasSize, edgeThreshold: threshold),
            .quarterBottomLeft
        )
        XCTAssertEqual(
            CanvasFractionRegion.proximityRegion(at: CGPoint(x: 1190, y: 790), canvasSize: canvasSize, edgeThreshold: threshold),
            .quarterBottomRight
        )
    }

    func testProximityRegionResolvesEdgesAwayFromCorners() {
        let canvasSize = CGSize(width: 1200, height: 800)
        let threshold: CGFloat = 50

        XCTAssertEqual(
            CanvasFractionRegion.proximityRegion(at: CGPoint(x: 600, y: 5), canvasSize: canvasSize, edgeThreshold: threshold),
            .full
        )
        XCTAssertEqual(
            CanvasFractionRegion.proximityRegion(at: CGPoint(x: 5, y: 400), canvasSize: canvasSize, edgeThreshold: threshold),
            .halfLeft
        )
        XCTAssertEqual(
            CanvasFractionRegion.proximityRegion(at: CGPoint(x: 1195, y: 400), canvasSize: canvasSize, edgeThreshold: threshold),
            .halfRight
        )
        XCTAssertEqual(
            CanvasFractionRegion.proximityRegion(at: CGPoint(x: 600, y: 795), canvasSize: canvasSize, edgeThreshold: threshold),
            .halfBottom
        )
    }

    func testProximityRegionReturnsNilForOpenMiddle() {
        let canvasSize = CGSize(width: 1200, height: 800)
        XCTAssertNil(
            CanvasFractionRegion.proximityRegion(at: CGPoint(x: 600, y: 400), canvasSize: canvasSize, edgeThreshold: 50)
        )
    }

    // MARK: - TileDistribution

    func testIdealShapeIsSingleStripUpToFourTilesHorizontal() {
        XCTAssertEqual(TileDistribution.idealShape(count: 3, axis: .horizontal), TileDistribution.GridShape(columns: 3, rows: 1))
        XCTAssertEqual(TileDistribution.idealShape(count: 4, axis: .horizontal), TileDistribution.GridShape(columns: 4, rows: 1))
    }

    func testIdealShapeIsSingleStripUpToFourTilesVertical() {
        XCTAssertEqual(TileDistribution.idealShape(count: 3, axis: .vertical), TileDistribution.GridShape(columns: 1, rows: 3))
        XCTAssertEqual(TileDistribution.idealShape(count: 4, axis: .vertical), TileDistribution.GridShape(columns: 1, rows: 4))
    }

    func testIdealShapeIsNearSquareGridFromFiveTilesHorizontal() {
        XCTAssertEqual(TileDistribution.idealShape(count: 5, axis: .horizontal), TileDistribution.GridShape(columns: 3, rows: 2))
        XCTAssertEqual(TileDistribution.idealShape(count: 6, axis: .horizontal), TileDistribution.GridShape(columns: 3, rows: 2))
        XCTAssertEqual(TileDistribution.idealShape(count: 7, axis: .horizontal), TileDistribution.GridShape(columns: 3, rows: 3))
        XCTAssertEqual(TileDistribution.idealShape(count: 9, axis: .horizontal), TileDistribution.GridShape(columns: 3, rows: 3))
        XCTAssertEqual(TileDistribution.idealShape(count: 10, axis: .horizontal), TileDistribution.GridShape(columns: 4, rows: 3))
    }

    func testIdealShapeIsNearSquareGridFromFiveTilesVertical() {
        XCTAssertEqual(TileDistribution.idealShape(count: 5, axis: .vertical), TileDistribution.GridShape(columns: 2, rows: 3))
        XCTAssertEqual(TileDistribution.idealShape(count: 6, axis: .vertical), TileDistribution.GridShape(columns: 2, rows: 3))
        XCTAssertEqual(TileDistribution.idealShape(count: 7, axis: .vertical), TileDistribution.GridShape(columns: 3, rows: 3))
    }

    func testFittingShapeReturnsIdealShapeWhenItAlreadyFits() {
        let shape = TileDistribution.fittingShape(count: 6, axis: .horizontal, canvasSize: CGSize(width: 1200, height: 800))
        XCTAssertEqual(shape, TileDistribution.GridShape(columns: 3, rows: 2))
    }

    func testFittingShapeFallsBackToASmallerShapeWhenTheIdealOneIsTooSmall() {
        // Ideal shape for 20 tiles horizontal is 5x4, whose 40pt-wide panes
        // don't fit a 200pt-wide canvas. Every returned shape's panes must
        // still meet the minimum tile size.
        let shape = TileDistribution.fittingShape(count: 20, axis: .horizontal, canvasSize: CGSize(width: 200, height: 600))
        XCTAssertNotNil(shape)
        if let shape {
            XCTAssertGreaterThanOrEqual(200 / CGFloat(shape.columns), DashboardTileMetrics.minWidth)
            XCTAssertGreaterThanOrEqual(600 / CGFloat(shape.rows), DashboardTileMetrics.minHeight)
        }
    }

    func testFittingShapeReturnsNilWhenNoShapeFits() {
        let shape = TileDistribution.fittingShape(count: 5, axis: .horizontal, canvasSize: CGSize(width: 10, height: 10))
        XCTAssertNil(shape)
    }

    func testCanDistributeMatchesFittingShapeAvailability() {
        XCTAssertTrue(TileDistribution.canDistribute(count: 6, axis: .horizontal, canvasSize: CGSize(width: 1200, height: 800)))
        XCTAssertFalse(TileDistribution.canDistribute(count: 5, axis: .horizontal, canvasSize: CGSize(width: 10, height: 10)))
        XCTAssertTrue(TileDistribution.canDistribute(count: 2, axis: .horizontal, canvasSize: CGSize(width: 1200, height: 800)))
        XCTAssertFalse(TileDistribution.canDistribute(count: 1, axis: .horizontal, canvasSize: CGSize(width: 1200, height: 800)))
    }

    func testDistributeReturnsEmptyForFewerThanTwoTiles() {
        let tiles = [
            DistributableTile(id: UUID(), offset: CGSize(width: 0, height: 0))
        ]
        let result = TileDistribution.distribute(tiles: tiles, axis: .horizontal, canvasSize: CGSize(width: 1200, height: 800))
        XCTAssertTrue(result.isEmpty)
    }

    func testDistributeHorizontallyProducesHalvesForTwoTiles() {
        let canvasSize = CGSize(width: 1200, height: 800)
        let a = DistributableTile(id: UUID(), offset: CGSize(width: 0, height: 0))
        let b = DistributableTile(id: UUID(), offset: CGSize(width: 600, height: 0))

        let result = TileDistribution.distribute(tiles: [b, a], axis: .horizontal, canvasSize: canvasSize)

        XCTAssertEqual(result[a.id], CanvasFractionRegion.halfLeft.rect(in: canvasSize))
        XCTAssertEqual(result[b.id], CanvasFractionRegion.halfRight.rect(in: canvasSize))
    }

    func testDistributeVerticallyProducesHalvesForTwoTiles() {
        let canvasSize = CGSize(width: 1200, height: 800)
        let a = DistributableTile(id: UUID(), offset: CGSize(width: 0, height: 0))
        let b = DistributableTile(id: UUID(), offset: CGSize(width: 0, height: 400))

        let result = TileDistribution.distribute(tiles: [b, a], axis: .vertical, canvasSize: canvasSize)

        XCTAssertEqual(result[a.id], CanvasFractionRegion.halfTop.rect(in: canvasSize))
        XCTAssertEqual(result[b.id], CanvasFractionRegion.halfBottom.rect(in: canvasSize))
    }

    func testDistributeReturnsEmptyForZeroCanvasSize() {
        let tiles = (0..<3).map {
            DistributableTile(id: UUID(), offset: CGSize(width: CGFloat($0) * 100, height: 0))
        }
        XCTAssertTrue(TileDistribution.distribute(tiles: tiles, axis: .horizontal, canvasSize: .zero).isEmpty)
    }

    func testDistributeHorizontallyIsUnchangedForFourTiles() {
        let canvasSize = CGSize(width: 1200, height: 800)
        let a = DistributableTile(id: UUID(), offset: CGSize(width: 0, height: 0))
        let b = DistributableTile(id: UUID(), offset: CGSize(width: 100, height: 0))
        let c = DistributableTile(id: UUID(), offset: CGSize(width: 200, height: 0))
        let d = DistributableTile(id: UUID(), offset: CGSize(width: 300, height: 0))

        let result = TileDistribution.distribute(tiles: [d, b, a, c], axis: .horizontal, canvasSize: canvasSize)

        XCTAssertEqual(result[a.id], CGRect(x: 0, y: 0, width: 300, height: 800))
        XCTAssertEqual(result[b.id], CGRect(x: 300, y: 0, width: 300, height: 800))
        XCTAssertEqual(result[c.id], CGRect(x: 600, y: 0, width: 300, height: 800))
        XCTAssertEqual(result[d.id], CGRect(x: 900, y: 0, width: 300, height: 800))
    }

    func testDistributeHorizontallyStretchesThePartialLastRowToFillTheCanvas() {
        let canvasSize = CGSize(width: 900, height: 600)
        // 7 tiles, offsets already ascending by width so sort order == creation order.
        let tiles = (0..<7).map { DistributableTile(id: UUID(), offset: CGSize(width: CGFloat($0) * 50, height: 0)) }

        let result = TileDistribution.distribute(tiles: tiles, axis: .horizontal, canvasSize: canvasSize)

        let sortedIDs = tiles.map { $0.id }
        // Rows 0-1 (indices 0-2, 3-5): 3 tiles each, 300pt wide, 200pt tall.
        for row in 0..<2 {
            for col in 0..<3 {
                let id = sortedIDs[row * 3 + col]
                XCTAssertEqual(result[id], CGRect(x: CGFloat(col) * 300, y: CGFloat(row) * 200, width: 300, height: 200))
            }
        }
        // Row 2 (index 6): 1 tile, stretched to the full 900pt width.
        XCTAssertEqual(result[sortedIDs[6]], CGRect(x: 0, y: 400, width: 900, height: 200))
    }

    func testDistributeVerticallyStretchesThePartialLastColumnToFillTheCanvas() {
        // Transpose of testDistributeHorizontallyStretchesThePartialLastRowToFillTheCanvas:
        // idealShape(7, .vertical) == GridShape(columns: 3, rows: 3), same shape as the
        // horizontal case, just filled column-major instead of row-major. This exercises
        // the vertical placement branch's x/y axis assignment (secondaryOrigin -> x,
        // primaryOrigin -> y) for 5+ tiles with a partial final column, which no other
        // test covers end-to-end.
        let canvasSize = CGSize(width: 600, height: 900)
        // 7 tiles, offsets already ascending by width so sort order == creation order.
        let tiles = (0..<7).map { DistributableTile(id: UUID(), offset: CGSize(width: CGFloat($0) * 70, height: 0)) }

        let result = TileDistribution.distribute(tiles: tiles, axis: .vertical, canvasSize: canvasSize)

        let sortedIDs = tiles.map { $0.id }
        // Columns 0-1 (indices 0-2, 3-5): 3 tiles each, 200pt wide, 300pt tall.
        for col in 0..<2 {
            for row in 0..<3 {
                let id = sortedIDs[col * 3 + row]
                XCTAssertEqual(result[id], CGRect(x: CGFloat(col) * 200, y: CGFloat(row) * 300, width: 200, height: 300))
            }
        }
        // Column 2 (index 6): 1 tile, stretched to the full 900pt height.
        XCTAssertEqual(result[sortedIDs[6]], CGRect(x: 400, y: 0, width: 200, height: 900))
    }

    func testDistributeGridFitsManyMoreTilesThanTheOldSingleStripCould() {
        // The old single-strip algorithm needed a 40pt pane for 20 horizontal
        // tiles on an 800pt-wide canvas and refused (below the 44pt
        // minimum). The grid algorithm distributes the same 20 tiles into a
        // 5x4 grid instead, whose panes comfortably clear the minimum.
        let tiles = (0..<20).map { DistributableTile(id: UUID(), offset: CGSize(width: CGFloat($0) * 40, height: 0)) }
        let result = TileDistribution.distribute(tiles: tiles, axis: .horizontal, canvasSize: CGSize(width: 800, height: 600))
        XCTAssertEqual(result.count, 20)
        for rect in result.values {
            XCTAssertGreaterThanOrEqual(rect.width, DashboardTileMetrics.minWidth)
            XCTAssertGreaterThanOrEqual(rect.height, DashboardTileMetrics.minHeight)
        }
    }

    func testDistributeReturnsEmptyWhenNoGridShapeFitsMinimumTileSize() {
        // No grid shape for 5 tiles can produce a 44pt pane on a 10x10
        // canvas — distributing would just produce overlapping tiles.
        let tiles = (0..<5).map { DistributableTile(id: UUID(), offset: CGSize(width: CGFloat($0) * 2, height: 0)) }
        let result = TileDistribution.distribute(tiles: tiles, axis: .horizontal, canvasSize: CGSize(width: 10, height: 10))
        XCTAssertTrue(result.isEmpty)
    }

    func testDistributeHorizontallyFillsCanvasInEqualColumns() {
        let canvasSize = CGSize(width: 1200, height: 800)
        let a = DistributableTile(id: UUID(), offset: CGSize(width: 0, height: 0))
        let b = DistributableTile(id: UUID(), offset: CGSize(width: 120, height: 0))
        let c = DistributableTile(id: UUID(), offset: CGSize(width: 300, height: 0))

        // Deliberately unsorted input.
        let result = TileDistribution.distribute(tiles: [c, a, b], axis: .horizontal, canvasSize: canvasSize)

        // Matches CanvasFractionRegion's thirds exactly for a 3-tile selection.
        XCTAssertEqual(result[a.id], CGRect(x: 0, y: 0, width: 400, height: 800))
        XCTAssertEqual(result[b.id], CGRect(x: 400, y: 0, width: 400, height: 800))
        XCTAssertEqual(result[c.id], CGRect(x: 800, y: 0, width: 400, height: 800))
    }

    func testDistributeHorizontallyPreservesLeadingEdgeOrder() {
        let canvasSize = CGSize(width: 1200, height: 800)
        let a = DistributableTile(id: UUID(), offset: CGSize(width: 0, height: 10))
        let b = DistributableTile(id: UUID(), offset: CGSize(width: 60, height: 10))
        let c = DistributableTile(id: UUID(), offset: CGSize(width: 260, height: 10))

        let result = TileDistribution.distribute(tiles: [a, b, c], axis: .horizontal, canvasSize: canvasSize)

        XCTAssertEqual(result[a.id], CGRect(x: 0, y: 0, width: 400, height: 800))
        XCTAssertEqual(result[b.id], CGRect(x: 400, y: 0, width: 400, height: 800))
        XCTAssertEqual(result[c.id], CGRect(x: 800, y: 0, width: 400, height: 800))
    }

    func testDistributeVerticallyFillsCanvasInEqualRows() {
        let canvasSize = CGSize(width: 1200, height: 900)
        let a = DistributableTile(id: UUID(), offset: CGSize(width: 5, height: 0))
        let b = DistributableTile(id: UUID(), offset: CGSize(width: 5, height: 120))
        let c = DistributableTile(id: UUID(), offset: CGSize(width: 5, height: 300))

        let result = TileDistribution.distribute(tiles: [b, c, a], axis: .vertical, canvasSize: canvasSize)

        XCTAssertEqual(result[a.id], CGRect(x: 0, y: 0, width: 1200, height: 300))
        XCTAssertEqual(result[b.id], CGRect(x: 0, y: 300, width: 1200, height: 300))
        XCTAssertEqual(result[c.id], CGRect(x: 0, y: 600, width: 1200, height: 300))
    }

    // MARK: - TileDistribution.distribute(tiles:into:) / isMultiTileSelection

    func testDistributeIntoRegionPicksHorizontalAxisForWideRegion() {
        let regionRect = CGRect(x: 100, y: 50, width: 900, height: 300)
        let a = DistributableTile(id: UUID(), offset: CGSize(width: 0, height: 0))
        let b = DistributableTile(id: UUID(), offset: CGSize(width: 500, height: 0))

        let result = TileDistribution.distribute(tiles: [a, b], into: regionRect)

        XCTAssertEqual(result?[a.id], CGRect(x: 100, y: 50, width: 450, height: 300))
        XCTAssertEqual(result?[b.id], CGRect(x: 550, y: 50, width: 450, height: 300))
    }

    func testDistributeIntoRegionPicksVerticalAxisForTallRegion() {
        let regionRect = CGRect(x: 20, y: 10, width: 300, height: 900)
        let a = DistributableTile(id: UUID(), offset: CGSize(width: 0, height: 0))
        let b = DistributableTile(id: UUID(), offset: CGSize(width: 0, height: 500))

        let result = TileDistribution.distribute(tiles: [a, b], into: regionRect)

        XCTAssertEqual(result?[a.id], CGRect(x: 20, y: 10, width: 300, height: 450))
        XCTAssertEqual(result?[b.id], CGRect(x: 20, y: 460, width: 300, height: 450))
    }

    func testDistributeIntoRegionReturnsNilWhenRegionTooSmall() {
        let regionRect = CGRect(x: 0, y: 0, width: 10, height: 10)
        let tiles = (0..<5).map { DistributableTile(id: UUID(), offset: CGSize(width: CGFloat($0) * 2, height: 0)) }

        XCTAssertNil(TileDistribution.distribute(tiles: tiles, into: regionRect))
    }

    func testDistributeIntoRegionReturnsNilForZeroSizeRegion() {
        let tiles = [
            DistributableTile(id: UUID(), offset: .zero),
            DistributableTile(id: UUID(), offset: CGSize(width: 10, height: 0))
        ]
        XCTAssertNil(TileDistribution.distribute(tiles: tiles, into: .zero))
    }

    func testIsMultiTileSelectionRequiresAnchorInSelectionAndAtLeastTwoTiles() {
        let anchor = UUID()
        let other = UUID()

        XCTAssertFalse(TileDistribution.isMultiTileSelection(anchorID: anchor, selectedTileIDs: [anchor]))
        XCTAssertFalse(TileDistribution.isMultiTileSelection(anchorID: anchor, selectedTileIDs: []))
        XCTAssertFalse(TileDistribution.isMultiTileSelection(anchorID: anchor, selectedTileIDs: [other]))
        XCTAssertTrue(TileDistribution.isMultiTileSelection(anchorID: anchor, selectedTileIDs: [anchor, other]))
    }

    // MARK: - SelectionToolbarPlacement

    func testShouldFlipBelowWhenAboveWouldClipTheViewportTop() {
        let rect = CGRect(x: 0, y: 10, width: 100, height: 50)
        let result = SelectionToolbarPlacement.shouldFlipBelow(selectionRect: rect, viewportZoom: 1, viewportPanY: 0)
        XCTAssertTrue(result)
    }

    func testShouldNotFlipBelowWithRoomAbove() {
        let rect = CGRect(x: 0, y: 100, width: 100, height: 50)
        let result = SelectionToolbarPlacement.shouldFlipBelow(selectionRect: rect, viewportZoom: 1, viewportPanY: 0)
        XCTAssertFalse(result)
    }

    func testShouldFlipBelowAccountsForPan() {
        let rect = CGRect(x: 0, y: 10, width: 100, height: 50)
        // A large positive pan pushes the canvas down on screen, so the same
        // selection that would clip at pan=0 now has room above it.
        let result = SelectionToolbarPlacement.shouldFlipBelow(selectionRect: rect, viewportZoom: 0.5, viewportPanY: 100)
        XCTAssertFalse(result)
    }
}
