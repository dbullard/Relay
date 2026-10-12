import Foundation
import SwiftUI

/// Stable, reference-identity-comparable home for the tile-canvas action
/// closures that used to be constructor parameters on `DashboardTileCanvas`
/// and `DashboardTileContainer`.
///
/// SwiftUI compares class references by identity (`===`), not structurally,
/// so a `DashboardCanvasActionCoordinator` instance is always "the same" to
/// SwiftUI's diffing across renders -- unlike a closure literal, which is a
/// "new" value every time it's constructed even if its captured behavior is
/// identical. `DashboardRootView` creates exactly one of these per canvas
/// (via plain `@State`, not `@StateObject` -- nothing here needs to trigger
/// a SwiftUI update, it only needs a stable identity) and reassigns its
/// closures on every render. That reassignment is cheap (a handful of
/// property writes) and invisible to view diffing, because it happens
/// inside a class, not as part of comparing `DashboardTileContainer`'s
/// stored properties.
@MainActor
final class DashboardCanvasActionCoordinator {
    // MARK: Tile-canvas level (previously DashboardTileCanvas's 6 closures)

    var onExitLiveMode: (() -> Void)?
    var onGroupMoveCommit: ((UUID, CGSize) -> Void)?
    var onSnapCommit: ((UUID, CanvasFractionRegion) -> Void)?
    var onPushUndoSnapshot: ((String) -> Void)?
    var onSaveTabs: (() -> Void)?
    var onScheduleTabsSaveDebounced: ((Bool) -> Void)?
    var onFocusTileForInspector: ((UUID) -> Void)?

    // MARK: Per-tile level (previously DashboardTileContainer's 11 closures)

    var onPrimarySelect: ((UUID) -> Void)?
    var onContextSelect: ((UUID) -> Void)?
    var onDragBegan: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onPersist: ((Bool) -> Void)?
    var onUndoSnapshot: ((String) -> Void)?
    var onResizeBegan: (() -> Void)?
    var onEditRequested: ((UUID, Bool) -> Void)?
    var onDraggingTilesChanged: ((Bool) -> Void)?

    // MARK: Tile/tab mutation (previously the write side of @Binding var tile/tab)

    var onSetTile: ((UUID, UUID, DashboardTileModel) -> Void)?
    var onSetTab: ((DashboardTab) -> Void)?

    // MARK: Live Mode interactive-tap tracking
    //
    // The canvas-wide double-tap-to-exit-Live-Mode gesture (see
    // `DashboardTileCanvas`) is a `.simultaneousGesture` on the container that
    // holds every tile, so it sees every tap in the canvas regardless of
    // which tile handled it -- including two taps on two different button
    // tiles fired in quick succession. `lastInteractiveTileTapAt` lets that
    // gesture tell "double-tapped empty canvas" (should exit) apart from
    // "tapped two different interactive tiles" (shouldn't): interactive
    // Live Mode module content stamps this on tap via
    // `recordInteractiveTileTap()`, and the exit gesture backs off if a tap
    // landed here within the double-tap window.
    var lastInteractiveTileTapAt: Date?

    init() {}

    // MARK: Forwarding calls -- every one is a safe no-op if unconfigured.

    func exitLiveMode() { onExitLiveMode?() }
    func recordInteractiveTileTap() { lastInteractiveTileTapAt = Date() }
    func groupMoveCommit(anchorID: UUID, translation: CGSize) { onGroupMoveCommit?(anchorID, translation) }
    func snapCommit(anchorID: UUID, region: CanvasFractionRegion) { onSnapCommit?(anchorID, region) }
    func pushUndoSnapshot(_ title: String) { onPushUndoSnapshot?(title) }
    func saveTabs() { onSaveTabs?() }
    func scheduleTabsSaveDebounced(reconcileGraphNodes: Bool) { onScheduleTabsSaveDebounced?(reconcileGraphNodes) }
    func focusTileForInspector(tileID: UUID) { onFocusTileForInspector?(tileID) }

    func primarySelect(tileID: UUID) { onPrimarySelect?(tileID) }
    func contextSelect(tileID: UUID) { onContextSelect?(tileID) }
    func dragBegan(tileID: UUID) { onDragBegan?(tileID) }
    func delete(tileID: UUID) { onDelete?(tileID) }
    func persist(reconcileGraphNodes: Bool) { onPersist?(reconcileGraphNodes) }
    func undoSnapshot(_ title: String) { onUndoSnapshot?(title) }
    func resizeBegan() { onResizeBegan?() }
    func editRequested(tileID: UUID, selectFirstModule: Bool) { onEditRequested?(tileID, selectFirstModule) }
    func draggingTilesChanged(_ isDragging: Bool) { onDraggingTilesChanged?(isDragging) }

    func setTile(tabID: UUID, tileID: UUID, to newValue: DashboardTileModel) { onSetTile?(tabID, tileID, newValue) }
    func setTab(_ newValue: DashboardTab) { onSetTab?(newValue) }
}
