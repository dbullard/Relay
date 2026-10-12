import SwiftUI

#if os(macOS)
import AppKit
#endif

struct DashboardTileCanvas: View {
    /// Max gap after an interactive-tile tap (see
    /// `DashboardCanvasActionCoordinator.lastInteractiveTileTapAt`) during
    /// which the canvas-wide double-tap-to-exit gesture stands down. Matches
    /// the rough scale of the system double-tap window so it only suppresses
    /// taps that could plausibly be the same two touches the exit gesture is
    /// reacting to.
    private static let interactiveTapSuppressionWindow: TimeInterval = 0.6

    /// Owned by the parent (`DashboardRootView`) so it can also read live drag
    /// state — e.g. to keep the selection action toolbar tracking a tile in
    /// real time while it's being dragged, instead of only after it commits.
    ///
    /// Plain `let`, not `@ObservedObject`/`@Bindable`: `DashboardTileInteractionSession`
    /// is `@Observable`, and this view's `body` does not read any of its
    /// per-frame gesture properties directly (the smart-guides read is
    /// isolated in `DashboardSmartGuidesLayer`, and per-tile drag/resize
    /// deltas are isolated in `DashboardTileLiveTransformHost` /
    /// `DashboardTileContainer`) -- so this view has nothing to observe here.
    let interactionSession: DashboardTileInteractionSession

    let tab: DashboardTab
    @Binding var selectedTileIDs: Set<UUID>
    @Binding var editingTileID: UUID?
    @Binding var isInspectorVisible: Bool
    /// Set when a tile should have its first module preselected the moment its
    /// settings inspector appears (currently only requested from double-click-to-edit).
    @Binding var pendingFirstModuleSelectTileID: UUID?
    @Binding var isDraggingTilesOnCanvas: Bool
    @Binding var selectionSource: TileSelectionSource
    @Binding var groupSelectionColor: Color?

    let sharedRosters: [DashboardRoster]
    let isLiveMode: Bool
    let liveModeReloadToken: UUID
    let allowTileOverlap: Bool
    let snapToGridEnabled: Bool
    let canvasSize: CGSize
    let canvasGuides: [CanvasGuide]
    let showGuidesEnabled: Bool
    let gridSizeSetting: Double
    let showGridEnabled: Bool
    let gridLineOpacity: Double
    let isPCORefreshing: Bool
    let viewportZoom: CGFloat

    /// The region of canvas space currently visible in the viewport
    /// (published by `DashboardCanvasViewportHost`, with hysteresis --
    /// see that type's doc comment). Defaults to `.infinite` ("cull
    /// nothing") for callers that don't sit inside a viewport host at all,
    /// e.g. the off-screen LAN-thumbnail renderer at the bottom of
    /// `DashboardRootView`, which needs every tile regardless of any
    /// on-screen viewport.
    var visibleCanvasRect: CGRect = .infinite

    /// Used only to compute tile bounding rects for the culling test in
    /// `DashboardCanvasVisibility.visibleTileIDs` -- matches the value
    /// `DashboardTileMetrics.effectiveSize` is called with everywhere else
    /// tile sizing is computed (`DashboardTileContainer`, `DashboardRootView`).
    var defaultTileSize: CGSize = CGSize(width: 260, height: 200)

    let disableDragging: Bool

    let actions: DashboardCanvasActionCoordinator
    var tileRemoteEditors: [UUID: [(name: String, color: Color)]] = [:]

    private struct TileRow: Identifiable {
        let id: UUID
        let snapshot: DashboardTileModel
        let isHidden: Bool
    }

    private func tileKindDiagnosticsKey(_ kind: DashboardTileKind) -> String {
        switch kind {
        case .empty: return "empty"
        case .person: return "person"
        case .pcoPlaceholder: return "pcoPlaceholder"
        case .time: return "time"
        }
    }

    private func prepareTileRowsForCanvas() -> [TileRow] {
        tab.tiles.map { tile in
            TileRow(id: tile.id, snapshot: tile, isHidden: tile.isHidden)
        }
    }

    private func recordCanvasTileMount(_ tile: DashboardTileModel) {
        RelayDiagnosticsStore.shared.incrementCounter("ui.canvas.tileMount")
        RelayDiagnosticsStore.shared.incrementCounter("ui.canvas.tileMount.kind.\(tileKindDiagnosticsKey(tile.kind))")
    }

    var body: some View {
        GeometryReader { geo in
            // Prefer the user-defined canvas size; fall back to the GeometryReader size
            // during the first layout pass when canvasSize can be zero.
            let w = canvasSize.width > 0 ? canvasSize.width : geo.size.width
            let h = canvasSize.height > 0 ? canvasSize.height : geo.size.height

            ZStack(alignment: .topLeading) {
                if !isLiveMode, showGridEnabled, gridSizeSetting > 0, gridLineOpacity > 0 {
                    GridBackground(
                        gridSize: CGFloat(gridSizeSetting),
                        lineOpacity: gridLineOpacity
                    )
                    .frame(width: w, height: h, alignment: .topLeading)
                    .clipped()
                    .allowsHitTesting(false)
                    .zIndex(0)
                }

                let tileRows = prepareTileRowsForCanvas()

                // Feature-flagged (`DashboardFeatureFlags.canvasViewportCulling`,
                // default off) viewport culling: skip mounting tiles that are
                // both off-screen and safe to unmount. `cullingEnabled` and
                // `visibleIDs` are computed once per body evaluation, not
                // per-tile, and touch nothing on `interactionSession` -- see
                // the `isDraggingTilesOnCanvas` note below for why.
                let cullingEnabled = DashboardFeatureFlags.canvasViewportCulling
                let visibleIDs: Set<UUID>? = cullingEnabled
                    ? DashboardCanvasVisibility.visibleTileIDs(
                        tiles: tab.tiles, defaultTileSize: defaultTileSize, visibleRect: visibleCanvasRect)
                    : nil

                SwiftUI.ForEach(tileRows, id: \.id) { (row: TileRow) in
                    let tileID = row.id
                    let isEditingVisual = (editingTileID == tileID)

                    // The mount decision itself lives in
                    // `DashboardCanvasCullingPolicy.shouldRender` (extracted
                    // so it's regression-tested independently of this view --
                    // see `DashboardCanvasCullingPolicyTests`). Note in
                    // particular that `isDraggingTilesOnCanvas` is a
                    // `@Binding<Bool>` toggled only at drag-begin/drag-end
                    // (see `DashboardTileContainer`'s
                    // `actions.draggingTilesChanged` calls), deliberately
                    // *not* `interactionSession.draggedTileID` -- reading
                    // that per-frame-reassigned property here would
                    // reintroduce the exact invalidation storm Task 2
                    // eliminated. `shouldRender`'s doc comment spells out the
                    // real cost this trades away: while any drag is in
                    // flight anywhere on the canvas, every previously-culled
                    // tile stays mounted for the gesture's whole duration,
                    // not just at its start and end.
                    let shouldRender = DashboardCanvasCullingPolicy.shouldRender(
                        tile: row.snapshot,
                        visibleTileIDs: visibleIDs,
                        isSelected: selectedTileIDs.contains(tileID),
                        isEditing: editingTileID == tileID,
                        isDraggingAnywhereOnCanvas: isDraggingTilesOnCanvas
                    )

                    if !row.isHidden, shouldRender {
                        DashboardTileLiveTransformHost(session: interactionSession, tileID: tileID) {
                            DashboardTileContainer(
                                tile: row.snapshot,
                                tab: tab,
                                interactionSession: interactionSession,
                                actions: actions,
                                sharedRosters: sharedRosters,
                                snapToGrid: snapToGridEnabled,
                                canvasSize: canvasSize,
                                guides: canvasGuides,
                                showGuidesEnabled: showGuidesEnabled,
                                gridSize: CGFloat(gridSizeSetting),
                                isSelected: selectedTileIDs.contains(tileID),
                                isLiveMode: isLiveMode,
                                liveModeReloadToken: liveModeReloadToken,
                                viewportZoom: viewportZoom,
                                selectionOutlineColor: (selectionSource == .overviewGroup) ? groupSelectionColor : nil,
                                allowTileOverlap: allowTileOverlap,
                                draggingDisabled: disableDragging,
                                selectedTileIDs: selectedTileIDs,
                                isPCORefreshing: isPCORefreshing,
                                isEditing: isEditingVisual,
                                remoteEditors: tileRemoteEditors[tileID] ?? []
                            )
                        }
                        .zIndex(1)
                        .onAppear {
                            recordCanvasTileMount(row.snapshot)
                        }
                    }
                }

                DashboardSmartGuidesLayer(session: interactionSession, canvasSize: CGSize(width: w, height: h))
                    .zIndex(100)

                DashboardSnapRegionPreviewLayer(session: interactionSession, canvasSize: CGSize(width: w, height: h))
                    .zIndex(101)
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        guard isLiveMode else { return }
                        // This gesture sits on the ZStack that contains every
                        // tile, so as a `.simultaneousGesture` it sees any two
                        // taps anywhere in the canvas within the double-tap
                        // window -- including one tap each on two different
                        // button tiles. Back off if an interactive tile (e.g.
                        // a button) was tapped moments ago; that's two
                        // deliberate presses, not a double-tap on empty canvas.
                        if let lastTap = actions.lastInteractiveTileTapAt,
                           Date().timeIntervalSince(lastTap) < Self.interactiveTapSuppressionWindow {
                            return
                        }
                        actions.exitLiveMode()
                    }
            )
        }
    }
}
