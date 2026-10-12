import SwiftUI

/// Applies a *group-drag follower's* live (uncommitted) drag delta without
/// making the tile's own body depend on the shared gesture session.
///
/// This does NOT apply to the tile actually being dragged (the "anchor") --
/// that tile has its own gesture and renders its own live position via
/// `DashboardTileContainer`'s native `@GestureState dragOffset`, which is
/// frame-perfect and never needs this relay. A follower has no gesture of
/// its own, so it has no other way to learn about the anchor's live delta
/// than reading it from the shared session here.
///
/// Follows the same principle as `DashboardCanvasViewportHost`: the
/// expensive content is built once, and only this small wrapper re-runs per
/// gesture frame. Combined with `@Observable`, a tile that is not
/// participating in the current gesture reads only `groupDragFollowerIDs`
/// here -- a value that changes once per gesture, not once per frame -- so
/// it is not invalidated at all while another tile is dragged. A
/// participating follower's `DashboardTileContainer` content is unaffected
/// by the delta changing (its inputs are unchanged), so SwiftUI's diffing
/// can reuse the already-built content and only re-apply this wrapper's
/// `.offset()`, instead of re-running the tile's full body (module stack,
/// resize handles, selection chrome, ~40 module-plugin views, etc.) on
/// every frame of the drag.
///
/// Group-resize deltas are intentionally NOT hoisted here (see
/// `DashboardTileContainer.groupResizeRenderHeightDelta` /
/// `groupResizeRenderOffsetYDelta`) -- a resize height change affects layout,
/// not just position, so an `.offset`-only wrapper can't express it. That
/// narrow read stays inside `DashboardTileContainer` itself.
struct DashboardTileLiveTransformHost<Content: View>: View {
    let session: DashboardTileInteractionSession
    let tileID: UUID
    @ViewBuilder let content: () -> Content

    private var dragDelta: CGSize {
        guard session.groupDragFollowerIDs.contains(tileID) else { return .zero }
        return session.groupDragDelta
    }

    var body: some View {
        content()
            .offset(x: dragDelta.width, y: dragDelta.height)
    }
}
