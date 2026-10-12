import Foundation

/// Whether viewport culling is allowed to unmount a tile's rendered view.
///
/// Unmounting a tile tears down its modules. For a module that owns a live
/// resource -- a socket, a stream, a continuous device poll, or an audio/OSC
/// tap (NDI, a WebView, Shure/Sennheiser wireless, an RTA, ...) -- that means
/// killing the resource mid-show and paying a reconnect cost that is far more
/// expensive than the render culling was meant to save. See
/// `NDIStreamRegistryBudgetTests` for the kind of acquire/release accounting
/// that a surprise unmount would disrupt.
///
/// Because of that asymmetry, this classification is deliberately
/// conservative: when genuinely unsure whether a module kind owns a live
/// resource, classify it as `true` (not cullable). The cost of
/// over-classifying is a slightly-less-optimized pan; the cost of
/// under-classifying is dropping a socket or audio tap mid-show.
enum DashboardCanvasCullingPolicy {
    /// `tile.modules` is optional: a nil/empty list means the tile renders
    /// through the legacy `DashboardTileKind` switch (`empty`/`person`/
    /// `pcoPlaceholder`/`time`), none of which owns a live resource.
    static func isCullable(_ tile: DashboardTileModel) -> Bool {
        guard let modules = tile.modules, !modules.isEmpty else { return true }
        return !modules.contains { holdsLiveResource($0.kind) }
    }

    /// Exhaustive by design -- **no `default:` case**. Adding a new
    /// `DashboardModuleKind` case must be a compile error here until someone
    /// explicitly decides whether it owns a live resource; that is the whole
    /// point of writing it this way instead of defaulting new kinds to
    /// "cullable" (which would be silently unsafe) or "not cullable" (which
    /// would silently defeat culling for future kinds without anyone
    /// noticing). Audited against the full current case list of
    /// `DashboardModuleKind` in `Dashboard/DashboardCoreModels.swift`.
    static func holdsLiveResource(_ kind: DashboardModuleKind) -> Bool {
        switch kind {
        // Owns a socket, a stream, a continuous device poll, or an audio/OSC
        // tap. Killing the view mid-gesture would drop the connection.
        case .ndi,                  // live video stream (NDIStreamRegistry-managed)
             .webpage,              // WKWebView session
             .youtubeStreamMonitor, // polls YouTube Live API for stream health
             .liveTranscription,    // microphone/audio-source tap + recognizer session
             .rta,                  // audio analysis tap
             .spectrograph,         // audio analysis tap
             .dawTransport,         // MIDI/OSC transport link
             .timecode,             // live timecode reader (LTC/MTC/etc.)
             .proPresenter,         // live ProPresenter connection
             .shureWireless,        // continuous device poll
             .shureOverview,        // continuous device poll
             .sennheiserWireless,   // continuous device poll
             .resolume,             // live OSC connection
             .dbReader:             // live audio-level tap
            return true

        // Static/derived content: renders from already-fetched data, local
        // state, or plain layout -- nothing is torn down by unmounting.
        case .person,
             .pcoRundown,
             .pcoTeamAssignments,
             .rosterTeamAssignments,
             .rosterPicker,
             .text,
             .image,
             .document,
             .separator,
             .time,
             .button:
            return false
        }
    }

    /// Whether `DashboardTileCanvas` should actually mount/render `tile`
    /// this frame. This is the exact decision the canvas view makes per
    /// tile, extracted into a free function so it's regression-testable
    /// independently of the view body (`DashboardCanvasCullingPolicyTests`).
    ///
    /// - `visibleTileIDs == nil` means culling itself is off (the feature
    ///   flag is disabled, or the caller -- e.g. the off-screen LAN-thumbnail
    ///   renderer -- doesn't sit inside a viewport at all): always render.
    /// - A tile that isn't `isCullable` (holds a live resource) always
    ///   renders, regardless of visibility.
    /// - A tile inside `visibleTileIDs` (on-screen, per
    ///   `DashboardCanvasVisibility.visibleTileIDs`) always renders.
    /// - A selected or actively-edited tile always renders, so group resize
    ///   (which only ever targets selected tiles) and the inspector never
    ///   lose their target while it's off-screen.
    /// - `isDraggingAnywhereOnCanvas` always renders, for *every* tile, for
    ///   the whole gesture -- not just the tile actually being dragged. This
    ///   is deliberately coarser than gating on the specific dragged tile's
    ///   ID: `DashboardTileInteractionSession.draggedTileID` is reassigned on
    ///   every `DragGesture.onChanged` frame (60-120x/second) even when its
    ///   value doesn't change, and `@Observable` does not suppress a
    ///   same-value re-write from invalidating an observer -- so gating on it
    ///   here would reintroduce, for every solo drag, the exact per-frame
    ///   canvas-body invalidation storm Task 2 eliminated. The real cost of
    ///   the coarser signal: for as long as any drag gesture is in flight
    ///   anywhere on the canvas, every previously-culled, off-screen tile
    ///   stays mounted and rendered -- not just twice (start/end), but for
    ///   the drag's entire duration. On a large dashboard where most tiles
    ///   are culled, any drag anywhere temporarily re-mounts all of them.
    ///   That's a real, deliberately-accepted cost, traded for the guarantee
    ///   that a dragged tile -- selected or not -- can never disappear
    ///   mid-drag, and for keeping this decision anchored to a binding that
    ///   only changes twice per gesture (drag-begin/drag-end) instead of one
    ///   that changes every frame.
    static func shouldRender(
        tile: DashboardTileModel,
        visibleTileIDs: Set<UUID>?,
        isSelected: Bool,
        isEditing: Bool,
        isDraggingAnywhereOnCanvas: Bool
    ) -> Bool {
        visibleTileIDs == nil
            || !isCullable(tile)
            || visibleTileIDs!.contains(tile.id)
            || isSelected
            || isEditing
            || isDraggingAnywhereOnCanvas
    }
}
