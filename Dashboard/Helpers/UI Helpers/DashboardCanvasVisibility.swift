import Foundation
import CoreGraphics

/// Pure geometry for viewport culling: which region of canvas space is
/// currently visible, and which tiles fall inside it.
///
/// Deliberately free of any SwiftUI/`@Observable` dependency so it's trivial
/// to unit test, and so nothing that touches it can accidentally couple a
/// view to gesture-frequency state. See `DashboardCanvasCullingPolicy` for
/// the separate (and safety-critical) question of *which* tiles are allowed
/// to be culled at all -- this type only answers "is it on-screen."
enum DashboardCanvasVisibility {
    /// The region of canvas space currently mapped into the viewport, expanded
    /// by `overscan` canvas points on every edge.
    ///
    /// Inverse of the transform the canvas is actually drawn with --
    /// `.scaleEffect(zoom, anchor: .topLeading)` then `.offset(pan)`, i.e.
    /// `screen = pan + zoom * canvasPoint`, so `canvasPoint = (screen - pan) / zoom`.
    /// This matches the inverse-transform arithmetic already used by
    /// `DashboardRootView.isPointInResizeHaloOfSelectedTile` / `guideAtPoint`
    /// (`(viewportPoint - canvasViewportPan) / zoom`).
    ///
    /// `overscan` is expressed in canvas points, so it must be applied
    /// *after* the `/ zoom` conversion, symmetrically on both origin and
    /// size. Subtracting `overscan` from the origin while adding
    /// `overscan * 2 / zoom` to the size (an earlier draft's mistake) is only
    /// symmetric at `zoom == 1` -- at any other zoom it pads one edge more
    /// than the opposite one. `testOverscanIsSymmetricAtNonUnitZoom` guards
    /// this specifically.
    ///
    /// Degenerate inputs (non-positive zoom, zero/negative viewport size --
    /// e.g. the first layout pass before geometry settles) fall back to
    /// `.infinite`, meaning "treat everything as visible" rather than risk
    /// culling every tile because of a divide-by-zero or inverted rect.
    static func visibleCanvasRect(
        viewportSize: CGSize, pan: CGSize, zoom: CGFloat, overscan: CGFloat
    ) -> CGRect {
        guard zoom > 0, viewportSize.width > 0, viewportSize.height > 0 else { return .infinite }
        return CGRect(
            x: -pan.width / zoom - overscan,
            y: -pan.height / zoom - overscan,
            width: viewportSize.width / zoom + overscan * 2,
            height: viewportSize.height / zoom + overscan * 2
        )
    }

    /// IDs of tiles whose (last-committed) bounding rect intersects
    /// `visibleRect`. An infinite `visibleRect` short-circuits to "everything
    /// is visible" rather than evaluating `CGRect.intersects` against an
    /// infinite rect tile-by-tile.
    static func visibleTileIDs(
        tiles: [DashboardTileModel], defaultTileSize: CGSize, visibleRect: CGRect
    ) -> Set<UUID> {
        guard !visibleRect.isInfinite else { return Set(tiles.map(\.id)) }
        return Set(tiles.lazy.filter { tile in
            CGRect(
                origin: CGPoint(x: tile.offset.width, y: tile.offset.height),
                size: DashboardTileMetrics.effectiveSize(for: tile, defaultTileSize: defaultTileSize)
            ).intersects(visibleRect)
        }.map(\.id))
    }

    /// Converts a margin expressed in **screen-space-equivalent points at
    /// zoom 1.0** into actual canvas points to use at `zoom`.
    ///
    /// `visibleCanvasRect` divides `pan` by `zoom` when converting to canvas
    /// space (`screen = pan + zoom * canvasPoint`), so the same real
    /// (screen-space) pan distance produces `1/zoom` times more canvas-space
    /// drift as the user zooms out. A flat, unscaled canvas-space overscan or
    /// hysteresis value tuned by feel at zoom 1.0 is therefore *not* the same
    /// real margin at other zoom levels -- at Relay's documented zoom floor
    /// of 0.25 (`ViewportPanZoomModifier.zoomRange`, echoed at
    /// `DashboardRootView.swift`'s local `zoomRange`), it represents 4x less
    /// real panning before being exhausted; at the 3.0 ceiling, 3x more.
    /// Dividing the nominal value by the live zoom keeps the *real* margin
    /// (in screen-space terms a user would actually feel) consistent across
    /// the whole range -- notably including 0.25x, which is both explicitly
    /// exercised in `docs/MANUAL_TESTING.md`'s culling checklist and exactly
    /// the situation (a zoomed-out view of a large, tile-heavy dashboard)
    /// where culling matters most.
    ///
    /// `zoomFloor` defends against dividing by a near-zero or corrupted zoom
    /// value (e.g. stale persisted data predating the documented zoom range)
    /// blowing this up; it defaults to that same 0.25 floor.
    static func canvasMargin(nominalScreenPoints: CGFloat, zoom: CGFloat, zoomFloor: CGFloat = 0.25) -> CGFloat {
        nominalScreenPoints / max(zoom, zoomFloor)
    }

    /// Whether the live viewport has drifted far enough from `published` to
    /// warrant republishing (and thus, via `DashboardCanvasViewportHost`'s
    /// `@State` write, a canvas rebuild). Compares each of the rect's four
    /// measures (origin.x, origin.y, width, height) independently -- any one
    /// exceeding `hysteresis` is enough to trigger a republish, since any of
    /// the four can expose an edge of the viewport that the stale `published`
    /// rect no longer covers.
    ///
    /// `hysteresis` should already be the zoom-scaled value from
    /// `canvasMargin`, not a raw nominal one -- this function itself is
    /// zoom-agnostic; it just compares whatever threshold it's given.
    static func shouldRepublishVisibleRect(candidate: CGRect, published: CGRect, hysteresis: CGFloat) -> Bool {
        guard !published.isInfinite, !candidate.isInfinite else { return true }
        return abs(candidate.origin.x - published.origin.x) > hysteresis
            || abs(candidate.origin.y - published.origin.y) > hysteresis
            || abs(candidate.width - published.width) > hysteresis
            || abs(candidate.height - published.height) > hysteresis
    }
}
