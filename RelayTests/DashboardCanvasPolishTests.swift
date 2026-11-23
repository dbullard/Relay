import XCTest
@testable import Relay

@MainActor
final class DashboardTileResizeHitTargetTests: XCTestCase {
    private let bigTile = CGSize(width: 600, height: 400)

    func testRadiusIsConstantOnScreenAcrossZoom() {
        for zoom: CGFloat in [0.25, 0.5, 1, 2, 3] {
            let radius = DashboardTileResizeHitTarget.hitRadius(viewportZoom: zoom, tileSize: bigTile, onScreenRadius: 14)
            XCTAssertEqual(radius * zoom, 14, accuracy: 0.0001, "zoom \(zoom)")
        }
    }

    func testIPadRadiusGivesA44PointTarget() {
        let radius = DashboardTileResizeHitTarget.hitRadius(viewportZoom: 0.5, tileSize: bigTile, onScreenRadius: 22)
        XCTAssertEqual(radius * 2 * 0.5, 44, accuracy: 0.0001)
    }

    func testRadiusIsCappedOnSmallTilesSoTheyStayMovable() {
        // 25% zoom would want 56 canvas points; a 90pt tile caps at a third of its side.
        let radius = DashboardTileResizeHitTarget.hitRadius(viewportZoom: 0.25, tileSize: CGSize(width: 90, height: 300), onScreenRadius: 14)
        XCTAssertEqual(radius, 30, accuracy: 0.0001)
    }

    func testCapNeverDropsBelowTheOriginalHalo() {
        let radius = DashboardTileResizeHitTarget.hitRadius(viewportZoom: 0.25, tileSize: CGSize(width: 30, height: 30), onScreenRadius: 14)
        XCTAssertEqual(radius, DashboardTileResizeHandleLayout.hitHalo, accuracy: 0.0001)
    }

    func testUnchangedResultIsNotAResize() {
        XCTAssertFalse(DashboardTileResizeHitTarget.resizeChangesTile(
            startSize: CGSize(width: 200, height: 100),
            startOffset: CGSize(width: 10, height: 20),
            newSize: CGSize(width: 200, height: 100),
            newOffsetY: 20,
            newOffsetX: nil
        ))
    }

    func testSizeOrOffsetChangeIsAResize() {
        let start = CGSize(width: 200, height: 100)
        let offset = CGSize(width: 10, height: 20)
        XCTAssertTrue(DashboardTileResizeHitTarget.resizeChangesTile(
            startSize: start, startOffset: offset,
            newSize: CGSize(width: 210, height: 100), newOffsetY: nil, newOffsetX: nil
        ))
        XCTAssertTrue(DashboardTileResizeHitTarget.resizeChangesTile(
            startSize: start, startOffset: offset,
            newSize: start, newOffsetY: 15, newOffsetX: nil
        ))
        XCTAssertTrue(DashboardTileResizeHitTarget.resizeChangesTile(
            startSize: start, startOffset: offset,
            newSize: start, newOffsetY: nil, newOffsetX: 4
        ))
    }
}

@MainActor
final class InspectorUndoCoalescerTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    func testSliderDragRegistersOneStep() {
        var coalescer = InspectorUndoCoalescer(window: 0.6)
        coalescer.beginContinuousEdit()
        var registered = 0
        for i in 0..<50 {
            // A slow drag: gaps longer than the window still fold while editing.
            if coalescer.shouldRegisterUndo(actionName: "Edit Tile Appearance", now: t0.addingTimeInterval(Double(i))) {
                registered += 1
            }
        }
        coalescer.endContinuousEdit(now: t0.addingTimeInterval(50))
        XCTAssertEqual(registered, 1)
    }

    func testFinalValueArrivingJustAfterDragEndFolds() {
        var coalescer = InspectorUndoCoalescer(window: 0.6)
        coalescer.beginContinuousEdit()
        XCTAssertTrue(coalescer.shouldRegisterUndo(actionName: "A", now: t0))
        coalescer.endContinuousEdit(now: t0.addingTimeInterval(2))
        XCTAssertFalse(coalescer.shouldRegisterUndo(actionName: "A", now: t0.addingTimeInterval(2.05)))
    }

    func testNewDragAlwaysStartsANewStep() {
        var coalescer = InspectorUndoCoalescer(window: 0.6)
        coalescer.beginContinuousEdit()
        XCTAssertTrue(coalescer.shouldRegisterUndo(actionName: "A", now: t0))
        coalescer.endContinuousEdit(now: t0.addingTimeInterval(0.1))
        coalescer.beginContinuousEdit()
        XCTAssertTrue(coalescer.shouldRegisterUndo(actionName: "A", now: t0.addingTimeInterval(0.2)))
    }

    func testRapidSameNameChangesFoldWithoutSession() {
        var coalescer = InspectorUndoCoalescer(window: 0.6)
        XCTAssertTrue(coalescer.shouldRegisterUndo(actionName: "Color", now: t0))
        XCTAssertFalse(coalescer.shouldRegisterUndo(actionName: "Color", now: t0.addingTimeInterval(0.3)))
        // The window slides with activity.
        XCTAssertFalse(coalescer.shouldRegisterUndo(actionName: "Color", now: t0.addingTimeInterval(0.8)))
        XCTAssertTrue(coalescer.shouldRegisterUndo(actionName: "Color", now: t0.addingTimeInterval(2)))
    }

    func testDifferentActionNameStartsANewStep() {
        var coalescer = InspectorUndoCoalescer(window: 0.6)
        coalescer.beginContinuousEdit()
        XCTAssertTrue(coalescer.shouldRegisterUndo(actionName: "A", now: t0))
        XCTAssertTrue(coalescer.shouldRegisterUndo(actionName: "B", now: t0.addingTimeInterval(0.1)))
    }
}

@MainActor
final class DashboardTileAccessibilityAdjustmentTests: XCTestCase {
    func testStepUsesGridWhenSnapping() {
        XCTAssertEqual(DashboardTileAccessibilityAdjustment.step(snapToGrid: true, gridSize: 25), 25)
        XCTAssertEqual(DashboardTileAccessibilityAdjustment.step(snapToGrid: false, gridSize: 25), 10)
        XCTAssertEqual(DashboardTileAccessibilityAdjustment.step(snapToGrid: true, gridSize: 0), 10)
    }

    func testTranslations() {
        XCTAssertEqual(DashboardTileAccessibilityAdjustment.translation(for: .left, step: 10), CGSize(width: -10, height: 0))
        XCTAssertEqual(DashboardTileAccessibilityAdjustment.translation(for: .right, step: 10), CGSize(width: 10, height: 0))
        XCTAssertEqual(DashboardTileAccessibilityAdjustment.translation(for: .up, step: 10), CGSize(width: 0, height: -10))
        XCTAssertEqual(DashboardTileAccessibilityAdjustment.translation(for: .down, step: 10), CGSize(width: 0, height: 10))
    }

    func testResizeClampsToMinimum() {
        let minimum = CGSize(width: 44, height: 44)
        XCTAssertEqual(
            DashboardTileAccessibilityAdjustment.resized(CGSize(width: 50, height: 100), by: .narrower, step: 10, minimum: minimum),
            CGSize(width: 44, height: 100)
        )
        XCTAssertEqual(
            DashboardTileAccessibilityAdjustment.resized(CGSize(width: 50, height: 100), by: .taller, step: 10, minimum: minimum),
            CGSize(width: 50, height: 110)
        )
    }

    func testOverlapDetection() {
        let moved = [CGRect(x: 0, y: 0, width: 100, height: 100)]
        XCTAssertTrue(DashboardTileAccessibilityAdjustment.overlaps(moved, obstacles: [CGRect(x: 90, y: 90, width: 50, height: 50)]))
        // Touching edges is not an overlap.
        XCTAssertFalse(DashboardTileAccessibilityAdjustment.overlaps(moved, obstacles: [CGRect(x: 100, y: 0, width: 50, height: 50)]))
    }
}

@MainActor
final class DashboardTileTapSequenceTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)

    func testFirstTapIsSingle() {
        var sequence = DashboardTileTapSequence()
        XCTAssertEqual(sequence.registerTap(at: t0, doubleTapInterval: 0.3), .single)
    }

    func testSecondQuickTapIsDouble() {
        var sequence = DashboardTileTapSequence()
        _ = sequence.registerTap(at: t0, doubleTapInterval: 0.3)
        XCTAssertEqual(sequence.registerTap(at: t0.addingTimeInterval(0.2), doubleTapInterval: 0.3), .double)
    }

    func testSlowSecondTapIsSingle() {
        var sequence = DashboardTileTapSequence()
        _ = sequence.registerTap(at: t0, doubleTapInterval: 0.3)
        XCTAssertEqual(sequence.registerTap(at: t0.addingTimeInterval(0.5), doubleTapInterval: 0.3), .single)
    }

    func testThirdQuickTapStartsOver() {
        var sequence = DashboardTileTapSequence()
        _ = sequence.registerTap(at: t0, doubleTapInterval: 0.3)
        _ = sequence.registerTap(at: t0.addingTimeInterval(0.1), doubleTapInterval: 0.3)
        XCTAssertEqual(sequence.registerTap(at: t0.addingTimeInterval(0.2), doubleTapInterval: 0.3), .single)
    }
}
