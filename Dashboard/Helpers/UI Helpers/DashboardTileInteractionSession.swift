import Foundation
import CoreGraphics
import Observation

/// Transient per-gesture state for group tile drag/resize.
///
/// During a multi-tile drag or resize, follower tiles read the relevant
/// delta here and apply it locally for rendering. `tab.tiles` itself is
/// only mutated once, when the gesture ends — see
/// `DashboardTileContainer.commitGroupResizeIfNeeded()` and the
/// `onGroupMoveCommit` callback.
///
/// `@Observable` (not `ObservableObject`) is load-bearing here: these values
/// are written 60-120 times per second during a gesture. Under
/// `ObservableObject`, every `@Published` write invalidated every observer
/// regardless of which property that observer actually read -- so one drag
/// frame re-ran the root body, the canvas body, and all N tile container
/// bodies (measured via Instruments: 1,050,087 incoming invalidation edges
/// on this class vs. 10,841 for the canvas's own body). With `@Observable`,
/// a view that only reads `groupDragFollowerIDs` is not invalidated when
/// `groupDragDelta` changes, so non-participating tiles stay untouched for
/// the whole gesture.
@MainActor
@Observable
final class DashboardTileInteractionSession {
    /// Cumulative translation (since gesture start) to apply to every tile
    /// whose ID is in `groupDragFollowerIDs`.
    var groupDragDelta: CGSize = .zero
    var groupDragFollowerIDs: Set<UUID> = []

    /// Cumulative height/offsetY deltas (since resize start) to apply to
    /// every tile whose ID is in `groupResizeFollowerIDs`.
    var groupResizeHeightDelta: CGFloat = 0
    var groupResizeOffsetYDelta: CGFloat = 0
    var groupResizeFollowerIDs: Set<UUID> = []

    /// Temporary smart guides generated during drag/resize snapping
    var activeSmartGuides: [SmartGuideLine] = []

    /// The tile currently being dragged directly (the "anchor" the user's cursor
    /// is on), and its live translation since gesture start. Unlike
    /// `groupDragDelta` (which only covers *follower* tiles in a multi-tile drag),
    /// this covers the anchor tile itself, in both solo and group drags — so UI
    /// anchored to tile position (like the selection action toolbar) can track
    /// the tile in real time instead of freezing until the drag commits.
    var draggedTileID: UUID? = nil
    var draggedTileDelta: CGSize = .zero

    /// The canvas-fraction region an active option-drag would snap into if
    /// released right now (nil when Option isn't held, or the drag isn't
    /// near an edge/corner) -- read by the live snap-region preview overlay.
    var activeSnapRegion: CanvasFractionRegion? = nil

    /// For a 2+ tile option-drag, the per-tile frames `activeSnapRegion`
    /// would resolve to on release, keyed by tile ID -- empty for a
    /// single-tile drag, where the preview only needs `activeSnapRegion`'s
    /// own `rect(in:)`.
    var activeSnapTileFrames: [UUID: CGRect] = [:]

    func reset() {
        groupDragDelta = .zero
        groupDragFollowerIDs = []
        groupResizeHeightDelta = 0
        groupResizeOffsetYDelta = 0
        groupResizeFollowerIDs = []
        activeSmartGuides.removeAll()
        draggedTileID = nil
        draggedTileDelta = .zero
        activeSnapRegion = nil
        activeSnapTileFrames = [:]
    }
}
