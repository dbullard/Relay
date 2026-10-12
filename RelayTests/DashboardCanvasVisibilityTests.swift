import XCTest
@testable import Relay

final class DashboardCanvasVisibilityTests: XCTestCase {

    func testVisibleRectMatchesInverseViewportTransform() {
        let rect = DashboardCanvasVisibility.visibleCanvasRect(
            viewportSize: CGSize(width: 800, height: 600),
            pan: CGSize(width: -400, height: -300), zoom: 2, overscan: 0
        )
        XCTAssertEqual(rect.origin.x, 200, accuracy: 0.001)
        XCTAssertEqual(rect.origin.y, 150, accuracy: 0.001)
        XCTAssertEqual(rect.width, 400, accuracy: 0.001)
        XCTAssertEqual(rect.height, 300, accuracy: 0.001)
    }

    /// Overscan is canvas-space and must expand the rect symmetrically at ANY zoom.
    /// A naive implementation that subtracts `overscan` from the origin but adds
    /// `overscan * 2 / zoom` to the size is only symmetric at zoom == 1 -- test
    /// across multiple zoom levels specifically to catch that class of bug.
    func testOverscanIsSymmetricAtNonUnitZoom() {
        for zoom in [CGFloat(0.25), 0.5, 1, 2, 3] {
            let bare = DashboardCanvasVisibility.visibleCanvasRect(
                viewportSize: CGSize(width: 800, height: 600), pan: .zero, zoom: zoom, overscan: 0)
            let padded = DashboardCanvasVisibility.visibleCanvasRect(
                viewportSize: CGSize(width: 800, height: 600), pan: .zero, zoom: zoom, overscan: 100)
            XCTAssertEqual(padded.minX, bare.minX - 100, accuracy: 0.001, "zoom \(zoom)")
            XCTAssertEqual(padded.maxX, bare.maxX + 100, accuracy: 0.001, "zoom \(zoom)")
            XCTAssertEqual(padded.minY, bare.minY - 100, accuracy: 0.001, "zoom \(zoom)")
            XCTAssertEqual(padded.maxY, bare.maxY + 100, accuracy: 0.001, "zoom \(zoom)")
        }
    }

    func testPanShiftsVisibleRect() {
        let rect = DashboardCanvasVisibility.visibleCanvasRect(
            viewportSize: CGSize(width: 800, height: 600),
            pan: CGSize(width: -1000, height: 0), zoom: 1, overscan: 0)
        XCTAssertEqual(rect.origin.x, 1000, accuracy: 0.001)
    }

    func testTileOutsideViewportIsNotVisible() {
        let tile = DashboardTileModel(id: UUID(), kind: .empty,
                                      offset: CGSize(width: 2000, height: 2000),
                                      size: CGSize(width: 200, height: 150))
        let ids = DashboardCanvasVisibility.visibleTileIDs(
            tiles: [tile], defaultTileSize: CGSize(width: 200, height: 150),
            visibleRect: CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertFalse(ids.contains(tile.id))
    }

    func testNonPositiveZoomFallsBackToRenderingEverything() {
        let tile = DashboardTileModel(id: UUID(), kind: .empty, offset: .zero,
                                      size: CGSize(width: 10, height: 10))
        let rect = DashboardCanvasVisibility.visibleCanvasRect(
            viewportSize: CGSize(width: 800, height: 600), pan: .zero, zoom: 0, overscan: 0)
        XCTAssertTrue(rect.isInfinite)
        XCTAssertTrue(DashboardCanvasVisibility.visibleTileIDs(
            tiles: [tile], defaultTileSize: .zero, visibleRect: rect).contains(tile.id))
    }

    // MARK: - canvasMargin(nominalScreenPoints:zoom:zoomFloor:)
    //
    // `visibleCanvasRect` divides `pan` by `zoom` when converting to canvas
    // space, so the same screen-space pan produces `1/zoom` times more
    // canvas-space drift as the user zooms out. `canvasMargin` converts a
    // margin expressed in screen-space-equivalent points at zoom 1.0 into
    // the actual canvas points to use at a given zoom, so overscan/hysteresis
    // behavior stays consistent in real (screen-space) terms across Relay's
    // documented zoom range (`ViewportPanZoomModifier.zoomRange`, 0.25...3.00).

    func testCanvasMarginAtZoomOneEqualsNominal() {
        XCTAssertEqual(DashboardCanvasVisibility.canvasMargin(nominalScreenPoints: 200, zoom: 1), 200, accuracy: 0.001)
    }

    func testCanvasMarginScalesInverselyWithZoom() {
        // At the app's zoom floor (0.25), the same real screen-space gesture
        // covers 4x more canvas distance, so the canvas-space margin must
        // grow by the same 4x to represent the same real screen distance.
        XCTAssertEqual(DashboardCanvasVisibility.canvasMargin(nominalScreenPoints: 200, zoom: 0.25), 800, accuracy: 0.001)
        // At 2x zoom, half as much canvas distance represents the same screen distance.
        XCTAssertEqual(DashboardCanvasVisibility.canvasMargin(nominalScreenPoints: 200, zoom: 2), 100, accuracy: 0.001)
    }

    func testCanvasMarginClampsToZoomFloorBelowIt() {
        // A zoom value below the app's documented floor (e.g. stale/corrupted
        // persisted data) must not blow up the margin via division by a
        // near-zero zoom -- clamp to the floor instead.
        XCTAssertEqual(
            DashboardCanvasVisibility.canvasMargin(nominalScreenPoints: 200, zoom: 0.01, zoomFloor: 0.25),
            800, accuracy: 0.001
        )
    }

    // MARK: - shouldRepublishVisibleRect(candidate:published:hysteresis:)

    func testShouldRepublishVisibleRectAlwaysTrueWhenPublishedIsInfinite() {
        let candidate = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertTrue(DashboardCanvasVisibility.shouldRepublishVisibleRect(
            candidate: candidate, published: .infinite, hysteresis: 200))
    }

    func testShouldRepublishVisibleRectFalseWhenDriftUnderThreshold() {
        let published = CGRect(x: 0, y: 0, width: 800, height: 600)
        let candidate = CGRect(x: 50, y: 0, width: 800, height: 600)
        XCTAssertFalse(DashboardCanvasVisibility.shouldRepublishVisibleRect(
            candidate: candidate, published: published, hysteresis: 200))
    }

    func testShouldRepublishVisibleRectTrueWhenOriginDriftExceedsThreshold() {
        let published = CGRect(x: 0, y: 0, width: 800, height: 600)
        let candidate = CGRect(x: 250, y: 0, width: 800, height: 600)
        XCTAssertTrue(DashboardCanvasVisibility.shouldRepublishVisibleRect(
            candidate: candidate, published: published, hysteresis: 200))
    }

    func testShouldRepublishVisibleRectTrueWhenSizeDriftExceedsThreshold() {
        let published = CGRect(x: 0, y: 0, width: 800, height: 600)
        let candidate = CGRect(x: 0, y: 0, width: 1100, height: 600)
        XCTAssertTrue(DashboardCanvasVisibility.shouldRepublishVisibleRect(
            candidate: candidate, published: published, hysteresis: 200))
    }

    /// Regression test for the zoom-floor bug: comparing drift against a flat,
    /// unscaled 200pt canvas-space hysteresis would trigger far too eagerly at
    /// the app's 0.25x zoom floor (where the same real pan produces 4x the
    /// canvas-space drift). `canvasMargin` must be used to scale both
    /// `hysteresis` and `overscan` by the live zoom before this comparison,
    /// not the raw nominal values.
    func testHysteresisGateAccountsForZoomAtZoomFloor() {
        let viewportSize = CGSize(width: 800, height: 600)
        let zoom: CGFloat = 0.25
        let scaledHysteresis = DashboardCanvasVisibility.canvasMargin(nominalScreenPoints: 200, zoom: zoom)
        let scaledOverscan = DashboardCanvasVisibility.canvasMargin(nominalScreenPoints: 600, zoom: zoom)

        let published = DashboardCanvasVisibility.visibleCanvasRect(
            viewportSize: viewportSize, pan: .zero, zoom: zoom, overscan: scaledOverscan)

        // An ordinary 100 screen-point pan at 0.25x zoom is 100/0.25 = 400
        // canvas points of drift -- comfortably under the correctly-scaled
        // 800pt threshold, so this must NOT trigger a republish.
        let smallCandidate = DashboardCanvasVisibility.visibleCanvasRect(
            viewportSize: viewportSize, pan: CGSize(width: -100, height: 0), zoom: zoom, overscan: scaledOverscan)
        XCTAssertFalse(DashboardCanvasVisibility.shouldRepublishVisibleRect(
            candidate: smallCandidate, published: published, hysteresis: scaledHysteresis))

        // A genuine ~210 screen-point pan (comfortably past the actual
        // screen-space design intent of ~200pt) at 0.25x zoom MUST still
        // trigger a republish once actually crossed.
        let bigCandidate = DashboardCanvasVisibility.visibleCanvasRect(
            viewportSize: viewportSize, pan: CGSize(width: -210, height: 0), zoom: zoom, overscan: scaledOverscan)
        XCTAssertTrue(DashboardCanvasVisibility.shouldRepublishVisibleRect(
            candidate: bigCandidate, published: published, hysteresis: scaledHysteresis))
    }
}
