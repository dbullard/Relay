import SwiftUI

#if os(macOS)
import AppKit
#endif

#if os(iOS)
import UIKit
#endif

struct DashboardTileContainer: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.proUpgradeAction) private var proUpgradeAction

    /// Returns true if PCO is configured (serviceTypeID is non-nil) for this tab.
    private var isPCOConfiguredForTab: Bool {
        tab.serviceTypeID != nil
    }

    let tile: DashboardTileModel
    let tab: DashboardTab
    /// Plain `let`, not `@ObservedObject`/`@Bindable` -- `DashboardTileInteractionSession`
    /// is `@Observable`, so reads made in `body` (and in computed properties body
    /// calls) are tracked automatically. This container's own body does NOT read
    /// `draggedTileDelta`/`groupDragDelta` -- this tile's own live drag position
    /// comes from its private `@GestureState dragOffset` instead (see the `.offset()`
    /// call near the bottom of `body`), and a *group-drag follower's* position comes
    /// from the wrapping `DashboardTileLiveTransformHost`, not from here. This
    /// container still reads `groupResizeHeightDelta`/`groupResizeOffsetYDelta`/
    /// `groupResizeFollowerIDs` directly (see `groupResizeRenderHeightDelta` etc.
    /// below) and still writes `draggedTileID`/`draggedTileDelta`/`groupDragDelta` to
    /// the session from its gesture handlers -- other consumers (the follower relay
    /// above, the root view's selection-toolbar tracking, smart guides) need those
    /// writes even though this view no longer reads them back for its own rendering.
    let interactionSession: DashboardTileInteractionSession
    let actions: DashboardCanvasActionCoordinator
    let sharedRosters: [DashboardRoster]
    let snapToGrid: Bool
    let canvasSize: CGSize
    let guides: [CanvasGuide]
    let showGuidesEnabled: Bool
    let gridSize: CGFloat
    let isSelected: Bool
    let isLiveMode: Bool
    let liveModeReloadToken: UUID
    let viewportZoom: CGFloat
    let selectionOutlineColor: Color?
    let allowTileOverlap: Bool
    let draggingDisabled: Bool
    let selectedTileIDs: Set<UUID>
    let isPCORefreshing: Bool
    let isEditing: Bool
    var remoteEditors: [(name: String, color: Color)] = []

    /// Synthetic `Binding` backed by the plain `tile` value for reads and
    /// `actions.setTile` for writes -- lets the ~40 child module-plugin
    /// views below keep receiving a fully-functional `Binding<DashboardTileModel>`
    /// even though `tile` itself is no longer a `@Binding`. Being a computed
    /// property (not stored), it's invisible to SwiftUI's structural
    /// comparison of this view's stored properties.
    private var tileBinding: Binding<DashboardTileModel> {
        Binding(
            get: { tile },
            set: { newValue in actions.setTile(tabID: tab.id, tileID: tile.id, to: newValue) }
        )
    }

    /// Synthetic `Binding` backed by the plain `tab` value for reads and
    /// `actions.setTab` for writes. See `tileBinding` above.
    private var tabBinding: Binding<DashboardTab> {
        Binding(
            get: { tab },
            set: { newValue in actions.setTab(newValue) }
        )
    }

    @GestureState private var dragOffset: CGSize = .zero
    @State private var lastDragTranslation: CGSize = .zero
    @State private var didBeginDrag: Bool = false
    @State private var isGroupResizeActive: Bool = false
    @State private var isTileResizeActive: Bool = false
    @State private var isPCORundownColumnResizeActive: Bool = false
    @State private var lastGroupResizeSize: CGSize = .zero
    @State private var lastGroupResizeOffsetY: CGFloat = 0

    private func moduleKindDiagnosticsKey(_ kind: DashboardModuleKind) -> String {
        switch kind {
        case .person: return "person"
        case .pcoRundown: return "pcoRundown"
        case .pcoTeamAssignments: return "pcoTeamAssignments"
        case .rosterTeamAssignments: return "rosterTeamAssignments"
        case .shureWireless: return "shureWireless"
        case .shureOverview: return "shureOverview"
        case .sennheiserWireless: return "sennheiserWireless"
        case .proPresenter: return "proPresenter"
        case .resolume: return "resolume"
        case .time: return "time"
        case .timecode: return "timecode"
        case .dawTransport: return "dawTransport"
        case .rosterPicker: return "rosterPicker"
        case .text: return "text"
        case .image: return "image"
        case .document: return "document"
        case .ndi: return "ndi"
        case .webpage: return "webpage"
        case .youtubeStreamMonitor: return "youtubeStreamMonitor"
        case .separator: return "separator"
        case .liveTranscription: return "liveTranscription"
        case .dbReader: return "dbReader"
        case .button: return "button"
        case .rta: return "rta"
        case .spectrograph: return "spectrograph"
        }
    }

    private func recordCanvasModuleMount(_ module: DashboardModuleModel) {
        RelayDiagnosticsStore.shared.incrementCounter("ui.canvas.moduleMount")
        RelayDiagnosticsStore.shared.incrementCounter("ui.canvas.moduleMount.kind.\(moduleKindDiagnosticsKey(module.kind))")
        // Timestamped, per-event companion to the counters above -- lets an
        // exported log show *when* and on *which* tile a module remounted,
        // instead of just a session-long total. See CANVAS MOUNT TRACE.
        let tileIDSuffix = tile.id.uuidString.prefix(8)
        let moduleIDSuffix = module.id.uuidString.prefix(8)
        RelayDiagnosticsStore.shared.recordCanvasMount(
            "mount kind=\(moduleKindDiagnosticsKey(module.kind)) tile=\(tileIDSuffix) module=\(moduleIDSuffix)"
        )
    }

    /// Default tile size for this container. Kept local so this nested type
    /// does not depend on instance members of the parent DashboardRootView.
    private var defaultTileSize: CGSize {
        #if os(iOS)
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let isCompact = (horizontalSizeClass == .compact)
        let scale: CGFloat = (isPad && !isCompact) ? 0.9 : 1.0
        let base = CGSize(width: 260, height: 200)
        return CGSize(width: base.width * scale, height: base.height * scale)
        #else
        return CGSize(width: 260, height: 200)
        #endif
    }

    private var effectiveSize: CGSize {
        DashboardTileMetrics.effectiveSize(for: tile, defaultTileSize: defaultTileSize)
    }

    private var tileCornerRadius: CGFloat {
        tile.cornerRadius
    }

    @ViewBuilder
    private func selectionOutlineLayer(size: CGSize) -> some View {
        let shouldShowSelectionChrome = (!isLiveMode && isSelected) || !activeSnapEdges.isEmpty
        if shouldShowSelectionChrome {
            let safeZoom = max(0.0001, viewportZoom)
            let outlineLineWidth = max(1, min(4, 2 / safeZoom))
            // Keep the selection stroke and resize handles in the same overlay layer
            // so the handles visually belong to the blue highlight outline.
            let outlineColor: Color = {
                if isOverlappingAnotherTile {
                    return .red
                }
                if isSelected, let override = selectionOutlineColor {
                    return override
                }
                return .accentColor
            }()

            ZStack {
                RoundedRectangle(cornerRadius: tileCornerRadius)
                    .strokeBorder(
                        outlineColor,
                        lineWidth: (isSelected && !isLiveMode) ? outlineLineWidth : 0
                    )
                    // Selection ring stays at the tile's bounds even though the
                    // resize-handles layer below intentionally extends past them.
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)

                // Handles are already gated by isLiveMode and by `showsIndicator`.
                // This layer is intentionally sized larger than the tile so the
                // 28pt resize-handle hit halos remain reachable past the edges.
                resizeHandlesLayer(size: size, interactionSession: interactionSession)
            }
        }
    }

    @ViewBuilder
    private func remotePresenceOverlay(size: CGSize) -> some View {
        let safeZoom = max(0.0001, viewportZoom)
        let ringWidth = max(1.5, 2 / safeZoom)
        let primary = remoteEditors[0].color

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: tileCornerRadius)
                .strokeBorder(primary, lineWidth: ringWidth)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 2) {
                // `remoteEditors` is an ephemeral presence snapshot handed down as a
                // `let`-equivalent struct property for this render pass (recomputed
                // by the parent canvas each frame); it cannot mutate mid-render, so
                // positional identity here is safe.
                ForEach(remoteEditors.indices, id: \.self) { i in
                    Text(remoteEditors[i].name)
                        .font(.system(size: max(8, 10 / safeZoom), weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 5 / safeZoom)
                        .padding(.vertical, 2 / safeZoom)
                        .background(remoteEditors[i].color)
                        .clipShape(RoundedRectangle(cornerRadius: 3 / safeZoom))
                }
            }
            .offset(y: -(remoteEditors.count == 1 ? 20 : CGFloat(remoteEditors.count) * 18 + 4) / safeZoom)
            .allowsHitTesting(false)
        }
    }

    private var isOverlappingAnotherTile: Bool {
        guard !allowTileOverlap, isSelected, !isLiveMode else { return false }

        let currentRect = CGRect(
            x: tile.offset.width + dragOffset.width,
            y: tile.offset.height + dragOffset.height,
            width: effectiveSize.width,
            height: effectiveSize.height
        )

        for other in tab.tiles where other.id != tile.id && !other.isHidden {
            let otherSize = DashboardTileSnappingHelper.effectiveSize(
                for: other,
                defaultTileSize: defaultTileSize
            )
            let otherRect = CGRect(
                x: other.offset.width,
                y: other.offset.height,
                width: otherSize.width,
                height: otherSize.height
            )
            if currentRect.intersects(otherRect) {
                return true
            }
        }

        return false
    }

    /// True when this tile is a non-anchor member of a group resize
    /// currently in progress (driven by the anchor tile's resize handle).
    private var isGroupResizeFollower: Bool {
        interactionSession.groupResizeFollowerIDs.contains(tile.id)
    }

    /// Height delta to layer on top of this tile's stored size while
    /// following a group resize. Zero otherwise.
    private var groupResizeRenderHeightDelta: CGFloat {
        isGroupResizeFollower ? interactionSession.groupResizeHeightDelta : 0
    }

    /// OffsetY delta to layer on top of this tile's stored offset while
    /// following a group resize. Zero otherwise.
    private var groupResizeRenderOffsetYDelta: CGFloat {
        isGroupResizeFollower ? interactionSession.groupResizeOffsetYDelta : 0
    }

    private func beginGroupResize() {
        isGroupResizeActive = true
        lastGroupResizeSize = effectiveSize
        lastGroupResizeOffsetY = tile.offset.height
        if shouldGroupResizeTogether() {
            interactionSession.groupResizeFollowerIDs = selectedTileIDs.subtracting([tile.id])
        }
    }

    private func endGroupResize() {
        isGroupResizeActive = false
    }

    /// Applies the session's accumulated group-resize deltas to every
    /// follower tile's stored model exactly once, then resets the session.
    /// Called from `onResizeEnded`.
    private func commitGroupResizeIfNeeded() {
        guard !interactionSession.groupResizeFollowerIDs.isEmpty else { return }

        let heightDelta = interactionSession.groupResizeHeightDelta
        let offsetYDelta = interactionSession.groupResizeOffsetYDelta
        let followerIDs = interactionSession.groupResizeFollowerIDs

        var updatedTab = tab
        for idx in updatedTab.tiles.indices where followerIDs.contains(updatedTab.tiles[idx].id) {
            var other = updatedTab.tiles[idx]

            if abs(heightDelta) > 0.1 {
                // Must match the size this follower is actually RENDERED at
                // (DashboardTileMetrics.effectiveSize, same helper `effectiveSize`
                // uses above and every DashboardTileContainer uses for its own
                // body) rather than DashboardTileSnappingHelper.effectiveSize.
                // The two disagree whenever `other.size` is nil: the snapping
                // helper falls back to the plain default tile size, while the
                // metrics helper derives a taller natural height from the
                // follower's own modules (e.g. a PCO Rundown tile renders at
                // 260pt even with no explicit size). Basing the post-resize
                // height on the wrong (shorter) baseline made an
                // auto-sized follower's committed height jump — usually
                // shrinking — right when the drag ended, even though its
                // live preview during the drag looked correct.
                let currentSize = DashboardTileMetrics.effectiveSize(
                    for: other,
                    defaultTileSize: defaultTileSize
                )
                let newHeight = max(DashboardTileMetrics.minHeight, currentSize.height + heightDelta)
                other.size = CGSize(width: currentSize.width, height: newHeight)
            }

            if abs(offsetYDelta) > 0.1 {
                other.offset.height += offsetYDelta
            }

            updatedTab.tiles[idx] = other
        }
        actions.setTab(updatedTab)

        interactionSession.reset()
    }

    private func shouldGroupResizeTogether() -> Bool {
        selectedTileIDs.count > 1 && selectedTileIDs.contains(tile.id)
    }

    @ViewBuilder
    private func resizeHandlesLayer(size: CGSize, interactionSession: DashboardTileInteractionSession) -> some View {
        let otherTileRects: [CGRect] = tab.tiles.filter { $0.id != tile.id }.map { other in
            let otherSize = DashboardTileSnappingHelper.effectiveSize(for: other, defaultTileSize: defaultTileSize)
            return CGRect(x: other.offset.width, y: other.offset.height, width: otherSize.width, height: otherSize.height)
        }

        DashboardTileResizeHandlesLayer(
            size: size,
            tileSize: tile.size,
            defaultSize: defaultTileSize,
            isLiveMode: isLiveMode,
            isSelected: isSelected,
            isGroupResizeMode: selectedTileIDs.count > 1 && selectedTileIDs.contains(tile.id),
            draggingDisabled: draggingDisabled,
            tileOffset: tile.offset,
            guides: guides,
            canvasSize: canvasSize,
            showGuidesEnabled: showGuidesEnabled,
            snapToGrid: snapToGrid,
            gridSize: gridSize,
            viewportZoom: viewportZoom,
            otherTileRects: otherTileRects,
            interactionSession: interactionSession,
            onResizeBegan: {
                isTileResizeActive = true
                actions.resizeBegan()
                beginGroupResize()
            },
            onResizeEnded: {
                isTileResizeActive = false
                commitGroupResizeIfNeeded()
                endGroupResize()
                actions.persist(reconcileGraphNodes: false)
            },
            onResizeChanged: handleResizeChanged
        )
    }

    /// Applies one resize-handle drag-changed event's full result -- new
    /// size and, when the dragged handle's orientation anchors the
    /// opposite edge, a new top and/or left offset -- as a SINGLE
    /// `actions.setTile` call.
    ///
    /// All affected fields are combined into one local `tile` snapshot
    /// before the single write. This is required because
    /// `ResizeHandle.applyResizeDrag` invokes `onResizeChanged` once per
    /// drag-changed event, synchronously, with no re-render in between --
    /// so a corner-handle drag that changes size AND an offset in the same
    /// event would, if each field were written via its own separate
    /// `actions.setTile` call, have each call read the same stale `tile`
    /// snapshot (since `tile` is a `let`, fixed for this whole render) and
    /// clobber whatever the previous call in the same event just wrote.
    private func handleResizeChanged(newSize: CGSize, newOffsetY: CGFloat?, newOffsetX: CGFloat?) {
        let previousSize = lastGroupResizeSize
        var updated = tile
        updated.size = newSize

        if let newOffsetY {
            updated.offset.height = newOffsetY
        }
        if let newOffsetX {
            updated.offset.width = newOffsetX
        }

        actions.setTile(tabID: tab.id, tileID: tile.id, to: updated)

        if isGroupResizeActive,
           shouldGroupResizeTogether(),
           abs(newSize.height - previousSize.height) > 0.1 {
            let deltaHeight = newSize.height - previousSize.height
            interactionSession.groupResizeHeightDelta += deltaHeight
        }
        if isGroupResizeActive {
            lastGroupResizeSize = newSize
        }

        if let newOffsetY {
            let deltaTop = newOffsetY - lastGroupResizeOffsetY
            if isGroupResizeActive, shouldGroupResizeTogether() {
                interactionSession.groupResizeOffsetYDelta += deltaTop
            }
            if isGroupResizeActive {
                lastGroupResizeOffsetY = newOffsetY
            }
        }
    }

    private struct DragSnapResult {
        let translation: CGSize
        let snapEdges: Set<DashboardTileSnapEdge>
        let smartGuides: [SmartGuideLine]
    }

    @State private var activeSnapEdges: Set<DashboardTileSnapEdge> = []

    private func updateActiveSnapEdgesIfNeeded(_ snapEdges: Set<DashboardTileSnapEdge>) {
        guard activeSnapEdges != snapEdges else { return }

        DispatchQueue.main.async {
            guard self.activeSnapEdges != snapEdges else { return }
            self.activeSnapEdges = snapEdges
        }
    }

    private func clearActiveSnapEdgesIfNeeded() {
        guard !activeSnapEdges.isEmpty else { return }
        activeSnapEdges.removeAll()
    }

    private func updateActiveSnapRegionIfNeeded(_ region: CanvasFractionRegion?, tileFrames: [UUID: CGRect]) {
        if interactionSession.activeSnapRegion != region {
            interactionSession.activeSnapRegion = region
        }
        if interactionSession.activeSnapTileFrames != tileFrames {
            interactionSession.activeSnapTileFrames = tileFrames
        }
    }

    private func clearActiveSnapRegionIfNeeded() {
        if interactionSession.activeSnapRegion != nil {
            interactionSession.activeSnapRegion = nil
        }
        if !interactionSession.activeSnapTileFrames.isEmpty {
            interactionSession.activeSnapTileFrames = [:]
        }
    }

    private var isTileSnapModifierActive: Bool {
        #if os(macOS)
        NSEvent.modifierFlags.contains(.shift)
        #else
        // On iOS, treat Snap-to-Grid enabled as "Shift held" so dragging live-snaps like macOS.
        snapToGrid
        #endif
    }

    private func dragSnapResult(
        rawTranslation: CGSize,
        tileSize: CGSize,
        isSnapModifierActive: Bool
    ) -> DragSnapResult {
        guard isSnapModifierActive else {
            return DragSnapResult(translation: rawTranslation, snapEdges: [], smartGuides: [])
        }

        var translation = rawTranslation
        var didSnapToGuideOrTile = false

        if showGuidesEnabled {
            let guideSnap = guideAndCanvasSnapResult(
                translation: translation,
                tileSize: tileSize
            )
            translation = guideSnap.translation
            didSnapToGuideOrTile = didSnapToGuideOrTile || !guideSnap.snapEdges.isEmpty
        }

        let proposedOffset = CGSize(
            width: tile.offset.width + translation.width,
            height: tile.offset.height + translation.height
        )
        let snapResult = DashboardTileSnappingHelper.snapOffsetToNearbyTiles(
            proposedOffset: proposedOffset,
            currentTileID: tile.id,
            in: tab,
            canvasSize: canvasSize,
            defaultTileSize: defaultTileSize
        )
        let snappedOffset = snapResult.offset

        let deltaX = snappedOffset.width - proposedOffset.width
        let deltaY = snappedOffset.height - proposedOffset.height

        if abs(deltaX) > 0.5 {
            didSnapToGuideOrTile = true
        }
        if abs(deltaY) > 0.5 {
            didSnapToGuideOrTile = true
        }

        translation = CGSize(
            width: snappedOffset.width - tile.offset.width,
            height: snappedOffset.height - tile.offset.height
        )

        // Live grid snapping while dragging when Snap to Grid is enabled and Shift is held (macOS)
        // or Snap-to-Grid is enabled (iOS). Skip grid snapping if guide or tile snapping already won.
        if snapToGrid, gridSize > 0, !didSnapToGuideOrTile {
            translation = gridSnappedTranslation(
                translation: translation
            )
        }

        let finalOffset = CGSize(
            width: tile.offset.width + translation.width,
            height: tile.offset.height + translation.height
        )
        return DragSnapResult(
            translation: translation,
            snapEdges: snapEdges(for: finalOffset, size: tileSize),
            smartGuides: snapResult.activeGuides
        )
    }

    private func guideAndCanvasSnapResult(
        translation: CGSize,
        tileSize: CGSize
    ) -> DragSnapResult {
        let rawX = tile.offset.width + translation.width
        let rawY = tile.offset.height + translation.height
        let left = rawX
        let right = rawX + tileSize.width
        let top = rawY
        let bottom = rawY + tileSize.height
        let snapThreshold: CGFloat = 30

        var snappedX = rawX
        var snappedY = rawY
        var bestDX = snapThreshold
        var bestDY = snapThreshold
        var horizontalEdge: DashboardTileSnapEdge?
        var verticalEdge: DashboardTileSnapEdge?

        if !guides.isEmpty {
            for guide in guides {
                switch guide.orientation {
                case .vertical:
                    let guideX = guide.position
                    let dxLeft = abs(guideX - left)
                    let dxRight = abs(guideX - right)
                    let dx = min(dxLeft, dxRight)
                    if dx < bestDX {
                        bestDX = dx
                        if dxLeft <= dxRight {
                            snappedX = guideX
                            horizontalEdge = .left
                        } else {
                            snappedX = guideX - tileSize.width
                            horizontalEdge = .right
                        }
                    }

                case .horizontal:
                    let guideY = guide.position
                    let dyTop = abs(guideY - top)
                    let dyBottom = abs(guideY - bottom)
                    let dy = min(dyTop, dyBottom)
                    if dy < bestDY {
                        bestDY = dy
                        if dyTop <= dyBottom {
                            snappedY = guideY
                            verticalEdge = .top
                        } else {
                            snappedY = guideY - tileSize.height
                            verticalEdge = .bottom
                        }
                    }
                }
            }
        }

        if canvasSize.width > 0 {
            let dxLeftEdge = abs(left)
            if dxLeftEdge < bestDX {
                bestDX = dxLeftEdge
                snappedX = 0
                horizontalEdge = .left
            }

            let dxRightEdge = abs(right - canvasSize.width)
            if dxRightEdge < bestDX {
                bestDX = dxRightEdge
                snappedX = canvasSize.width - tileSize.width
                horizontalEdge = .right
            }
        }

        if canvasSize.height > 0 {
            let dyTopEdge = abs(top)
            if dyTopEdge < bestDY {
                bestDY = dyTopEdge
                snappedY = 0
                verticalEdge = .top
            }

            let dyBottomEdge = abs(bottom - canvasSize.height)
            if dyBottomEdge < bestDY {
                bestDY = dyBottomEdge
                snappedY = canvasSize.height - tileSize.height
                verticalEdge = .bottom
            }
        }

        var edges: Set<DashboardTileSnapEdge> = []
        if bestDX < snapThreshold, let horizontalEdge {
            edges.insert(horizontalEdge)
        }
        if bestDY < snapThreshold, let verticalEdge {
            edges.insert(verticalEdge)
        }

        return DragSnapResult(
            translation: CGSize(
                width: snappedX - tile.offset.width,
                height: snappedY - tile.offset.height
            ),
            snapEdges: edges,
            smartGuides: []
        )
    }

    private func gridSnappedTranslation(translation: CGSize) -> CGSize {
        let proposedOffset = CGSize(
            width: tile.offset.width + translation.width,
            height: tile.offset.height + translation.height
        )
        let snappedX = (proposedOffset.width / gridSize).rounded() * gridSize
        let snappedY = (proposedOffset.height / gridSize).rounded() * gridSize

        return CGSize(
            width: snappedX - tile.offset.width,
            height: snappedY - tile.offset.height
        )
    }

    private func isInResizeHandleHitArea(_ point: CGPoint, size: CGSize) -> Bool {
        guard !isLiveMode, isSelected else { return false }

        // Match ResizeHandle's 28pt hit frame so the move-drag gesture defers
        // to the resize handle anywhere the resize cursor is shown.
        let hitRadius = DashboardTileResizeHandleLayout.hitHalo
        let layout = DashboardTileResizeHandleLayout(size: size)

        func near(_ target: CGPoint) -> Bool {
            hypot(point.x - target.x, point.y - target.y) <= hitRadius
        }

        // In group-resize mode, `DashboardTileResizeHandlesLayer` only
        // renders and hit-tests the top/bottom edge handles (see its
        // `isGroupResizeMode` branch and the `allowedOrientations` filter
        // passed to `DashboardResizeInteractionSurface`) -- the corner and
        // left/right positions have no live handle behind them. Reserving
        // those positions here too, unconditionally, created a dead zone:
        // a drag started there was blocked from moving the tile (this
        // guard said "that's a resize handle") but no resize handle was
        // actually there to pick it up either, so the drag silently did
        // nothing -- or, once the cursor drifted a few points outside the
        // 14pt hit radius, fell into an ordinary (and group-following)
        // tile move, which read as the tile "randomly" moving instead of
        // resizing. Only reserve the positions that are actually live for
        // the current mode so the fallback to move-drag is consistent.
        if shouldGroupResizeTogether() {
            return near(layout.topEdge) || near(layout.bottomEdge)
        }

        return near(layout.topLeft)
            || near(layout.topRight)
            || near(layout.bottomRight)
            || near(layout.bottomLeft)
            || near(layout.leftEdge)
            || near(layout.rightEdge)
            || near(layout.topEdge)
            || near(layout.bottomEdge)
    }

    var body: some View {
        tileContainerView
    }

    @ViewBuilder
    private var tileContainerView: some View {
        let baseSize = effectiveSize
        let size = CGSize(
            width: baseSize.width,
            height: max(DashboardTileMetrics.minHeight, baseSize.height + groupResizeRenderHeightDelta)
        )
        let formatting = TileTextFormatting(
            fontSize: tile.textFontSize,
            fontWeight: tile.textFontWeight,
            textColor: tile.textColor,
            capitalization: tile.textCapitalization,
            justification: tile.textJustification,
            verticalAlignment: tile.textVerticalAlignment
        )
        let coreTile = DashboardTileShell(
            tile: tile,
            size: size,
            cornerRadius: tileCornerRadius,
            activeSnapEdges: activeSnapEdges,
            isLiveMode: isLiveMode
        ) {
            tileView(size: size)
                .environment(\.tileTextFormatting, formatting)
        }

        let interactiveTile = coreTile
            .overlay {
                if isSelected || !activeSnapEdges.isEmpty {
                    selectionOutlineLayer(size: size)
                        .allowsHitTesting(!isLiveMode)
                }
            }
            .overlay {
                if !remoteEditors.isEmpty && !isLiveMode {
                    remotePresenceOverlay(size: size)
                }
            }
            .overlay(alignment: .top) {
                if isTileResizeActive {
                    DashboardTileResizeSizeHUD(size: size)
                        .offset(y: -28)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: isTileResizeActive)
            .contentShape(Rectangle())
            // This tile's OWN drag is rendered via `dragOffset`, SwiftUI's native
            // `@GestureState` -- private to this view instance, updated in lockstep
            // with the gesture recognizer, and never the cause of the invalidation
            // storm fixed elsewhere in this file (a `@GestureState` change never
            // invalidates sibling views). Regressed once (moved entirely to the
            // `interactionSession`-relayed path below, which added a cross-view
            // indirection and caused visible drag jitter), then restored.
            //
            // Only a *group-drag follower* (no gesture of its own) needs the
            // `interactionSession` relay, applied by the wrapping
            // `DashboardTileLiveTransformHost` via `.offset()` around this whole
            // view. `groupResizeRenderOffsetYDelta` is the comparatively rare
            // group-resize case, which also has no gesture of its own here.
            .offset(
                x: tile.offset.width + dragOffset.width,
                y: tile.offset.height + dragOffset.height + groupResizeRenderOffsetYDelta
            )
            .zIndex(
                (isEditing)
                ? 15           // actively edited tiles on top of all tiles
                : (isSelected ? 10 : 0) // selected tiles above unselected tiles
            )
            .onChange(of: isPCORundownColumnResizeActive) { _, isActive in
                guard isActive else { return }
                didBeginDrag = false
                lastDragTranslation = .zero
                interactionSession.reset()
                actions.draggingTilesChanged(false)
            }
            .onChange(of: isLiveMode) { _, isLive in
                guard isLive,
                      isTileResizeActive
                        || isGroupResizeActive
                        || !interactionSession.groupResizeFollowerIDs.isEmpty
                else { return }
                isTileResizeActive = false
                endGroupResize()
                interactionSession.reset()
            }

        let dragGesture = DragGesture()
            .updating($dragOffset) { value, state, transaction in
                transaction.disablesAnimations = true
                guard !isLiveMode, !draggingDisabled, !isPCORundownColumnResizeActive, !isTileResizeActive else { return }
                guard !isInResizeHandleHitArea(value.startLocation, size: size) else { return }

                let snapResult = dragSnapResult(
                    rawTranslation: value.translation,
                    tileSize: size,
                    isSnapModifierActive: isTileSnapModifierActive
                )
                state = snapResult.translation

                updateActiveSnapEdgesIfNeeded(snapResult.snapEdges)
            }
                .onChanged { value in
                    guard !isLiveMode, !draggingDisabled, !isPCORundownColumnResizeActive, !isTileResizeActive else {
                        didBeginDrag = false
                        lastDragTranslation = .zero
                        interactionSession.reset()
                        actions.draggingTilesChanged(false)
                        return
                    }
                    guard !isInResizeHandleHitArea(value.startLocation, size: size) else { return }
                    let snapResult = dragSnapResult(
                        rawTranslation: value.translation,
                        tileSize: size,
                        isSnapModifierActive: isTileSnapModifierActive
                    )
                    let currentTranslation = snapResult.translation
                    updateActiveSnapEdgesIfNeeded(snapResult.snapEdges)
                    interactionSession.activeSmartGuides = snapResult.smartGuides

                    let delta = CGSize(
                        width: currentTranslation.width - lastDragTranslation.width,
                        height: currentTranslation.height - lastDragTranslation.height
                    )

                    guard abs(delta.width) > 0.001 || abs(delta.height) > 0.001 else {
                        return
                    }

                    if !didBeginDrag {
                        didBeginDrag = true
                        actions.dragBegan(tileID: tile.id)
                        actions.draggingTilesChanged(true)
                        if selectedTileIDs.count > 1, selectedTileIDs.contains(tile.id) {
                            interactionSession.groupDragFollowerIDs = selectedTileIDs.subtracting([tile.id])
                        }
                    }

                    lastDragTranslation = currentTranslation
                    // Animation-disabled to match `dragOffset`'s `@GestureState` update
                    // above (`transaction.disablesAnimations = true`) -- without this,
                    // this `@Observable` write picks up whatever ambient transaction is
                    // active and lags visibly behind the tile's own animation-disabled
                    // render, which reads as the selection toolbar (anchored to this
                    // state) rubber-banding behind the dragged tile.
                    withTransaction(Transaction(animation: nil)) {
                        interactionSession.draggedTileID = tile.id
                        interactionSession.draggedTileDelta = currentTranslation
                        if !interactionSession.groupDragFollowerIDs.isEmpty {
                            interactionSession.groupDragDelta = currentTranslation
                        }
                    }

                    #if os(macOS)
                    if NSEvent.modifierFlags.contains(.option) {
                        // `tile.offset` is the tile's last *snapped* rendered position, and
                        // `currentTranslation` is this gesture's snap-quantized delta from
                        // `dragSnapResult` above -- neither alone tracks the raw cursor.
                        // Adding `value.location` (the cursor's position within the tile's
                        // own frame) on top looks like double-counting, but it's what
                        // cancels the snap quantization back out and recovers the true,
                        // unsnapped cursor position in canvas space. Don't simplify this.
                        let cursorInCanvas = CGPoint(
                            x: tile.offset.width + currentTranslation.width + value.location.x,
                            y: tile.offset.height + currentTranslation.height + value.location.y
                        )
                        // Fixed 32pt apparent on-screen threshold, normalized for zoom --
                        // same approach `SelectionActionToolbarView.chromeScale` uses to
                        // keep its own chrome a constant screen size regardless of zoom.
                        let edgeThreshold: CGFloat = 32 / max(0.0001, viewportZoom)

                        if let region = CanvasFractionRegion.proximityRegion(
                            at: cursorInCanvas,
                            canvasSize: canvasSize,
                            edgeThreshold: edgeThreshold
                        ) {
                            if TileDistribution.isMultiTileSelection(anchorID: tile.id, selectedTileIDs: selectedTileIDs) {
                                let distributable = tab.tiles
                                    .filter { selectedTileIDs.contains($0.id) }
                                    .map { DistributableTile(id: $0.id, offset: $0.offset) }
                                if let frames = TileDistribution.distribute(tiles: distributable, into: region.rect(in: canvasSize)) {
                                    updateActiveSnapRegionIfNeeded(region, tileFrames: frames)
                                } else {
                                    clearActiveSnapRegionIfNeeded()
                                }
                            } else {
                                updateActiveSnapRegionIfNeeded(region, tileFrames: [:])
                            }
                        } else {
                            clearActiveSnapRegionIfNeeded()
                        }
                    } else {
                        clearActiveSnapRegionIfNeeded()
                    }
                    #endif
                }
                .onEnded { value in
                    guard !isLiveMode, !draggingDisabled, !isPCORundownColumnResizeActive, !isTileResizeActive else {
                        didBeginDrag = false
                        lastDragTranslation = .zero
                        interactionSession.reset()
                        actions.draggingTilesChanged(false)
                        return
                    }
                    guard !isInResizeHandleHitArea(value.startLocation, size: size) else {
                        lastDragTranslation = .zero
                        clearActiveSnapEdgesIfNeeded()
                        interactionSession.activeSmartGuides.removeAll()
                        actions.draggingTilesChanged(false)
                        return
                    }

                    let finalTranslation = lastDragTranslation
                    lastDragTranslation = .zero
                    interactionSession.activeSmartGuides.removeAll()

                    // Clear live-tracking state now, synchronously, before the tile's
                    // own `offset` is committed below — avoids a frame where both the
                    // committed offset and a stale live delta would apply at once.
                    interactionSession.draggedTileID = nil
                    interactionSession.draggedTileDelta = .zero

                    #if os(macOS)
                    if let snapRegion = interactionSession.activeSnapRegion {
                        interactionSession.reset()
                        actions.snapCommit(anchorID: tile.id, region: snapRegion)
                        clearActiveSnapEdgesIfNeeded()
                        didBeginDrag = false
                        actions.draggingTilesChanged(false)
                        return
                    }
                    #endif

                    if !interactionSession.groupDragFollowerIDs.isEmpty {
                        actions.groupMoveCommit(anchorID: tile.id, translation: finalTranslation)
                        interactionSession.reset()
                    }

                    var newX = tile.offset.width + finalTranslation.width
                    var newY = tile.offset.height + finalTranslation.height

                    #if os(macOS)
                    let isShiftDown = NSEvent.modifierFlags.contains(.shift)
                    #else
                    // On iOS, treat Snap-to-Grid enabled as "Shift held" so dragging live-snaps like macOS.
                    let isShiftDown = snapToGrid
                    #endif

                    func snap(_ v: CGFloat) -> CGFloat {
                        let step = gridSize
                        return (v / step).rounded() * step
                    }

                    if snapToGrid, !isShiftDown {
                        newX = snap(newX)
                        newY = snap(newY)
                    }

                    // Allow tiles to live outside the canvas bounds; use the
                    // "Bring All Tiles Into Canvas" command to recover.

                    if !allowTileOverlap {
                        let proposedRect = CGRect(
                            x: newX,
                            y: newY,
                            width: effectiveSize.width,
                            height: effectiveSize.height
                        )

                        var overlapsAnotherTile = false
                        for other in tab.tiles where other.id != tile.id {
                            let otherSize = DashboardTileSnappingHelper.effectiveSize(for: other, defaultTileSize: defaultTileSize)
                            let otherRect = CGRect(
                                x: other.offset.width,
                                y: other.offset.height,
                                width: otherSize.width,
                                height: otherSize.height
                            )

                            if proposedRect.intersects(otherRect) {
                                overlapsAnotherTile = true
                                break
                            }
                        }

                        if overlapsAnotherTile {
                            newX = tile.offset.width
                            newY = tile.offset.height
                        }
                    }
                    var updated = tile
                    updated.offset.width = newX
                    updated.offset.height = newY
                    actions.setTile(tabID: tab.id, tileID: tile.id, to: updated)

                    actions.persist(reconcileGraphNodes: false)
                    clearActiveSnapEdgesIfNeeded()

                    didBeginDrag = false
                    actions.draggingTilesChanged(false)
                }

        let tileWithGestures = Group {
            if isLiveMode {
                interactiveTile
            } else {
                interactiveTile
                    // Let explicit child controls, like rundown column resize handles,
                    // own their drag gestures without also moving the entire tile.
                    .gesture(dragGesture, including: .gesture)
                    .onTapGesture(count: 2) {
                        if !(selectedTileIDs.count > 1 && selectedTileIDs.contains(tile.id)) {
                            actions.primarySelect(tileID: tile.id)
                        }
                        actions.editRequested(tileID: tile.id, selectFirstModule: true)
                    }
                    .onTapGesture {
                        actions.primarySelect(tileID: tile.id)
                    }
                    .contextMenu {
                        DashboardTileContextMenu(
                            tile: tileBinding,
                            tab: tabBinding,
                            isEmptyTile: isEmptyTile,
                            isLiveMode: isLiveMode,
                            snapToGrid: snapToGrid,
                            gridSize: gridSize,
                            selectedTileIDs: selectedTileIDs,
                            onEditRequested: { selectFirstModule in
                                actions.editRequested(tileID: tile.id, selectFirstModule: selectFirstModule)
                            },
                            onDelete: { actions.delete(tileID: tile.id) },
                            onPersist: { reconcileGraphNodes in
                                actions.persist(reconcileGraphNodes: reconcileGraphNodes)
                            },
                            onAlignSelectedTilesToGrid: alignSelectedTilesToGrid,
                            onResolveTileOverlapsToGrid: resolveTileOverlapsToGrid,
                            onDistributeSpacingHorizontally: distributeSpacingHorizontally,
                            onDistributeSpacingVertically: distributeSpacingVertically
                        )
                    }
            }
        }

        tileWithGestures
            .modifier(
                DashboardTileAccessibilityModifier(
                    tile: tile,
                    modules: resolvedModules ?? [],
                    isSelected: isSelected,
                    isLiveMode: isLiveMode,
                    onSelect: { actions.primarySelect(tileID: tile.id) },
                    onEdit: {
                        if !(selectedTileIDs.count > 1 && selectedTileIDs.contains(tile.id)) {
                            actions.primarySelect(tileID: tile.id)
                        }
                        actions.editRequested(tileID: tile.id, selectFirstModule: false)
                    },
                    onDelete: { actions.delete(tileID: tile.id) },
                    onExitLiveMode: { actions.exitLiveMode() }
                )
            )
            // Removed .onChange and .sheet for showingTileEditor; editing now handled at root.
    }

    private func snapEdges(for offset: CGSize, size: CGSize) -> Set<DashboardTileSnapEdge> {
        var edges: Set<DashboardTileSnapEdge> = []
        let epsilon: CGFloat = 0.5
        let rect = CGRect(
            x: offset.width,
            y: offset.height,
            width: size.width,
            height: size.height
        )

        if showGuidesEnabled {
            for guide in guides {
                switch guide.orientation {
                case .vertical:
                    if abs(rect.minX - guide.position) <= epsilon {
                        edges.insert(.left)
                    }
                    if abs(rect.maxX - guide.position) <= epsilon {
                        edges.insert(.right)
                    }
                case .horizontal:
                    if abs(rect.minY - guide.position) <= epsilon {
                        edges.insert(.top)
                    }
                    if abs(rect.maxY - guide.position) <= epsilon {
                        edges.insert(.bottom)
                    }
                }
            }
        }

        if canvasSize.width > 0 {
            if abs(rect.minX - 0) <= epsilon {
                edges.insert(.left)
            }
            if abs(rect.maxX - canvasSize.width) <= epsilon {
                edges.insert(.right)
            }
        }
        if canvasSize.height > 0 {
            if abs(rect.minY - 0) <= epsilon {
                edges.insert(.top)
            }
            if abs(rect.maxY - canvasSize.height) <= epsilon {
                edges.insert(.bottom)
            }
        }

        for other in tab.tiles where other.id != tile.id && !other.isHidden {
            let otherSize = DashboardTileSnappingHelper.effectiveSize(
                for: other,
                defaultTileSize: defaultTileSize
            )
            let otherRect = CGRect(
                x: other.offset.width,
                y: other.offset.height,
                width: otherSize.width,
                height: otherSize.height
            )

            if abs(rect.minX - otherRect.minX) <= epsilon || abs(rect.minX - otherRect.maxX) <= epsilon {
                edges.insert(.left)
            }
            if abs(rect.maxX - otherRect.minX) <= epsilon || abs(rect.maxX - otherRect.maxX) <= epsilon {
                edges.insert(.right)
            }
            if abs(rect.minY - otherRect.minY) <= epsilon || abs(rect.minY - otherRect.maxY) <= epsilon {
                edges.insert(.top)
            }
            if abs(rect.maxY - otherRect.minY) <= epsilon || abs(rect.maxY - otherRect.maxY) <= epsilon {
                edges.insert(.bottom)
            }
        }

        return edges
    }

    private var resolvedModules: [DashboardModuleModel]? {
        if let modules = tile.modules, !modules.isEmpty {
            return modules
        }

        // Legacy fallback: synthesize a single module for older saved tiles.
        //
        // `id` is pinned to `tile.id` rather than left to default to a fresh
        // `UUID()` on every call. This is a computed property re-evaluated on
        // every body re-render of this container, so leaving it random meant
        // the synthesized module got a brand-new identity each time --
        // ForEach saw that as the old module disappearing and a new one
        // appearing, forcing SwiftUI to tear down and remount it (re-running
        // its full onAppear setup) on every single re-render instead of just
        // updating it in place. `tile.id` is stable and, since each tile only
        // ever synthesizes one such module, is guaranteed not to collide with
        // any other module's id.
        switch tile.kind {
        case .empty:
            return nil
        case .person(let personModel):
            return [DashboardModuleModel(kind: .person(personModel), order: 0, id: tile.id)]
        case .time:
            return [DashboardModuleModel(kind: .time, order: 0, id: tile.id, timeConfig: TimeModuleConfig.default())]
        case .pcoPlaceholder:
            // Treat legacy placeholders as their modern module equivalents.
            return [DashboardModuleModel(kind: .pcoRundown, order: 0, id: tile.id, pcoConfig: PCOModuleConfig.rundownDefault())]
        }
    }

    @ViewBuilder private func tileView(size: CGSize) -> some View {
        if let modules = resolvedModules, !modules.isEmpty {
            let plan = DashboardModuleLayoutPlan(
                modules: modules,
                layout: tile.moduleLayout,
                tileSize: size,
                contentPadding: tile.contentPadding ?? 12
            )

            DashboardTileModuleStack(
                plan: plan,
                alignment: DashboardTileModuleMetadata.contentAlignment(
                    horizontal: tile.textJustification,
                    vertical: tile.textVerticalAlignment
                ),
                moduleContent: { module, allocatedHeight in
                    moduleView(
                        for: module,
                        maxHeight: allocatedHeight,
                        modulesSorted: plan.modules,
                        layout: plan.layout
                    )
                },
                onModuleAppear: { module in
                    recordCanvasModuleMount(module)
                }
            )
        } else {
            DashboardEmptyTilePlaceholder(contentPadding: tile.contentPadding ?? 12)
        }
    }

    private var isEmptyTile: Bool {
        let hasModules = !(tile.modules?.isEmpty ?? true)
        return !hasModules && tile.kind == .empty
    }
    @ViewBuilder
    private func moduleView(
        for module: DashboardModuleModel,
        maxHeight: CGFloat?,
        modulesSorted: [DashboardModuleModel],
        layout: TileModuleLayout
    ) -> some View {
        let style = DashboardTileModuleMetadata.cornerStyle(
            for: module,
            modulesSorted: modulesSorted,
            layout: layout
        )
        // Always apply ModuleCorners so single modules get full rounding and
        // stacked modules use top/middle/bottom styles without fighting the
        // outer tile clip.
        let shouldClipForStack = true
        let liveModeInteractionAllowed = !isLiveMode || module.allowsInteractionLiveMode
        let shouldForceLiveReload: Bool = {
            switch module.kind {
            case .liveTranscription, .dbReader:
                return true
            default:
                return false
            }
        }()
        let liveReloadID = shouldForceLiveReload
            ? "\(module.id.uuidString)-\(liveModeReloadToken.uuidString)"
            : module.id.uuidString

        if !module.kind.isAvailableInCurrentBuild {
            UnavailableModuleView(
                title: DashboardTileModuleMetadata.label(for: module),
                message: module.kind.unavailableInCurrentBuildMessage
            )
            .modifier(
                ModuleCornerClip(
                    radius: tileCornerRadius,
                    style: style,
                    enabled: shouldClipForStack
                )
            )
            .id(liveReloadID)
            .allowsHitTesting(false)
        } else if module.kind.requiresPro && !subscriptionManager.hasPro {
            ProLockedModuleView(
                title: DashboardTileModuleMetadata.label(for: module),
                onUpgrade: proUpgradeAction
            )
            .modifier(
                ModuleCornerClip(
                    radius: tileCornerRadius,
                    style: style,
                    enabled: shouldClipForStack
                )
            )
            .id(liveReloadID)
            .allowsHitTesting(liveModeInteractionAllowed)
        } else {
            Group {
                switch module.kind {
        case .person:
            ZStack(alignment: .topTrailing) {
                if let plugin = DashboardModuleRegistry.plugin(for: module.kind) {
                    let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)

                    plugin.tileView(
                        tab: tabBinding,
                        tile: tileBinding,
                        module: moduleBinding,
                        isLiveMode: isLiveMode
                    )
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                } else {
                    // fallback (should be rare)
                    if case .person(let personModel) = module.kind {
                        PersonTileView(model: tab.resolvedPersonModel(personModel), syncGroupID: tab.syncGroupID)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if isPCORefreshing {
                    ProgressView()
                        .scaleEffect(0.7)
                        .padding(4)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                        .padding(4)
                }
            }
            .modifier(
                ModuleCornerClip(
                    radius: tileCornerRadius,
                    style: style,
                    enabled: shouldClipForStack
                )
            )
        case .pcoRundown:
            let constrainedMaxHeight: CGFloat? = {
                guard let maxHeight, maxHeight < DashboardTileMetrics.pcoRundownNaturalHeight else {
                    return nil
                }
                return maxHeight
            }()
            Group {
                if DashboardModuleRegistry.plugin(for: module.kind) != nil {
                    let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)

                    PCOTileView(
                        tab: tabBinding,
                        moduleConfig: moduleBinding.wrappedValue.pcoConfig,
                        moduleConfigBinding: Binding(
                            get: { moduleBinding.wrappedValue.pcoConfig ?? PCOModuleConfig.rundownDefault() },
                            set: { newValue in
                                var updated = moduleBinding.wrappedValue
                                updated.pcoConfig = newValue
                                moduleBinding.wrappedValue = updated
                            }
                        ),
                        onRundownColumnResizeActiveChanged: { isActive in
                            isPCORundownColumnResizeActive = isActive
                        }
                    )
                } else {
                    // Fallback: render directly if plugin registry can't be resolved.
                    PCOTileView(
                        tab: tabBinding,
                        moduleConfig: module.pcoConfig,
                        onRundownColumnResizeActiveChanged: { isActive in
                            isPCORundownColumnResizeActive = isActive
                        }
                    )
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: constrainedMaxHeight ?? .infinity,
                alignment: .topLeading
            )
            .clipped()
            .overlay(bottomFadeOverlay(maxHeight: constrainedMaxHeight))
            .modifier(
                ModuleCornerClip(
                    radius: tileCornerRadius,
                    style: style,
                    enabled: shouldClipForStack
                )
            )
        case .pcoTeamAssignments:
            // Reuse the same constrained-height treatment as Rundown so the
            // tile can size itself naturally when there's room.
            let constrainedMaxHeight: CGFloat? = {
                guard let maxHeight, maxHeight < DashboardTileMetrics.pcoRundownNaturalHeight else {
                    return nil
                }
                return maxHeight
            }()
            Group {
                if let plugin = DashboardModuleRegistry.plugin(for: module.kind) {
                    let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)

                    plugin.tileView(
                        tab: tabBinding,
                        tile: tileBinding,
                        module: moduleBinding,
                        isLiveMode: isLiveMode
                    )
                } else {
                    Text("PCO Team Assignments unavailable")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: constrainedMaxHeight ?? .infinity,
                alignment: .topLeading
            )
            .clipped()
            .overlay(bottomFadeOverlay(maxHeight: constrainedMaxHeight))
            .modifier(
                ModuleCornerClip(
                    radius: tileCornerRadius,
                    style: style,
                    enabled: shouldClipForStack
                )
            )
        case .rosterTeamAssignments:
            Group {
                if tile.modules?.contains(where: { $0.id == module.id }) == true {
                    let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)
                    let configBinding = Binding<RosterTeamAssignmentsConfig>(
                        get: {
                            moduleBinding.wrappedValue.rosterTeamAssignmentsConfig
                                ?? RosterTeamAssignmentsConfig.defaults()
                        },
                        set: { newValue in
                            var updated = moduleBinding.wrappedValue
                            updated.rosterTeamAssignmentsConfig = newValue
                            moduleBinding.wrappedValue = updated
                        }
                    )

                    RosterTeamAssignmentsModuleView(
                        config: configBinding,
                        tab: tab,
                        sharedRosters: sharedRosters
                    )
                } else {
                    Text("Roster Team Assignments unavailable")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .modifier(
                ModuleCornerClip(
                    radius: tileCornerRadius,
                    style: style,
                    enabled: shouldClipForStack
                )
            )
        case .shureWireless:
            // Render each Shure module from its own per-module configuration so
            // multiple Shure modules on the same tile can show different channels.
            if let modules = tile.modules,
               let idx = modules.firstIndex(where: { $0.id == module.id }) {

                // Snapshot the current per-module config, or use a default if missing.
                let cfg = tile.modules?[idx].shureConfig ?? ShureModuleConfig.default()

                // Only apply a vertical constraint to the Shure module when
                // the allocated maxHeight is smaller than its typical natural
                // height; otherwise we let it size itself and skip the fade.
                let constrainedMaxHeight: CGFloat? = {
                    guard let maxHeight, maxHeight < DashboardTileMetrics.shureNaturalHeight else {
                        return nil
                    }
                    return maxHeight
                }()

                ShureWirelessModuleView(
                    selectedChannel: Binding(
                        get: {
                            tile.modules?[idx].shureConfig?.selectedChannel
                        },
                        set: { newValue in
                            guard tile.modules?.indices.contains(idx) == true else { return }
                            var updated = tile
                            // Ensure there is a config, then update the selection.
                            if updated.modules?[idx].shureConfig == nil {
                                updated.modules?[idx].shureConfig = ShureModuleConfig.default()
                            }
                            updated.modules?[idx].shureConfig?.selectedChannel = newValue
                            actions.setTile(tabID: tab.id, tileID: tile.id, to: updated)
                        }
                    ),
                    showsHeader: tile.showsTitle,
                    isLiveMode: isLiveMode,
                    showDeviceName: cfg.showDeviceName,
                    showChannelName: cfg.showChannelName,
                    showIPPort: cfg.showIPPort,
                    showFrequency: cfg.showFrequency,
                    showBattery: cfg.showBattery,
                    showRFStrength: cfg.showRFStrength,
                    showAudioMeter: cfg.showAudioMeter,
                    demoEnabled: cfg.demoEnabled,
                    demoIsIem: cfg.demoIsIem,
                    demoMicName: cfg.demoMicName,
                    demoDeviceName: cfg.demoDeviceName,
                    demoBatteryPercent: cfg.demoBatteryPercent,
                    demoFrequencyMHz: cfg.demoFrequencyMHz
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: constrainedMaxHeight ?? .infinity,
                    alignment: .topLeading
                )
                .clipped()
                .overlay(bottomFadeOverlay(maxHeight: constrainedMaxHeight))
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            } else {
                // If we somehow can't resolve the backing module, show an empty
                // Shure module state so the UI remains stable.
                let cfg = ShureModuleConfig.default()
                let constrainedMaxHeight: CGFloat? = {
                    guard let maxHeight, maxHeight < DashboardTileMetrics.shureNaturalHeight else {
                        return nil
                    }
                    return maxHeight
                }()

                ShureWirelessModuleView(
                    selectedChannel: .constant(nil),
                    showsHeader: tile.showsTitle,
                    isLiveMode: isLiveMode,
                    showDeviceName: true,
                    showChannelName: true,
                    showIPPort: false,
                    showFrequency: true,
                    showBattery: true,
                    showRFStrength: true,
                    showAudioMeter: cfg.showAudioMeter,
                    demoEnabled: cfg.demoEnabled,
                    demoIsIem: cfg.demoIsIem,
                    demoMicName: cfg.demoMicName,
                    demoDeviceName: cfg.demoDeviceName,
                    demoBatteryPercent: cfg.demoBatteryPercent,
                    demoFrequencyMHz: cfg.demoFrequencyMHz
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: constrainedMaxHeight ?? .infinity,
                    alignment: .topLeading
                )
                .clipped()
                .overlay(bottomFadeOverlay(maxHeight: constrainedMaxHeight))
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            }
        case .shureOverview:
            if let modules = tile.modules,
               let idx = modules.firstIndex(where: { $0.id == module.id }) {
                let constrainedMaxHeight: CGFloat? = {
                    guard let maxHeight, maxHeight < DashboardTileMetrics.shureNaturalHeight else {
                        return nil
                    }
                    return maxHeight
                }()

                ShureOverviewModuleView(
                    config: Binding(
                        get: { tile.modules?[idx].shureOverviewConfig ?? ShureOverviewModuleConfig.default() },
                        set: { newValue in
                            guard tile.modules?.indices.contains(idx) == true else { return }
                            var updated = tile
                            if updated.modules?[idx].shureOverviewConfig == nil {
                                updated.modules?[idx].shureOverviewConfig = ShureOverviewModuleConfig.default()
                            }
                            updated.modules?[idx].shureOverviewConfig = newValue
                            actions.setTile(tabID: tab.id, tileID: tile.id, to: updated)
                        }
                    ),
                    isLiveMode: isLiveMode
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: constrainedMaxHeight ?? .infinity,
                    alignment: .topLeading
                )
                .clipped()
                .overlay(bottomFadeOverlay(maxHeight: constrainedMaxHeight))
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            } else {
                let constrainedMaxHeight: CGFloat? = {
                    guard let maxHeight, maxHeight < DashboardTileMetrics.shureNaturalHeight else {
                        return nil
                    }
                    return maxHeight
                }()
                ShureOverviewModuleView(config: .constant(.default()), isLiveMode: isLiveMode)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: constrainedMaxHeight ?? .infinity,
                        alignment: .topLeading
                    )
                    .clipped()
                    .overlay(bottomFadeOverlay(maxHeight: constrainedMaxHeight))
                    .modifier(
                        ModuleCornerClip(
                            radius: tileCornerRadius,
                            style: style,
                            enabled: shouldClipForStack
                        )
                    )
            }
        case .sennheiserWireless:
            // Render via plugin just like other modern modules
            if let plugin = DashboardModuleRegistry.plugin(for: module.kind) {
                let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)

                plugin.tileView(
                    tab: tabBinding,
                    tile: tileBinding,
                    module: moduleBinding,
                    isLiveMode: isLiveMode
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: maxHeight ?? .infinity,
                    alignment: .topLeading
                )
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )

            } else {
                // Fallback: render with the module config so demo mode still works.
                let cfg = module.sennheiserConfig ?? SennheiserWirelessModuleConfig()
                SennheiserWirelessTileView(
                    config: cfg,
                    isLiveMode: isLiveMode,
                    showsHeader: tile.showsTitle
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: maxHeight ?? .infinity,
                    alignment: .topLeading
                )
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            }
        case .proPresenter:
            if let plugin = DashboardModuleRegistry.plugin(for: module.kind) {
                let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)

                plugin.tileView(
                    tab: tabBinding,
                    tile: tileBinding,
                    module: moduleBinding,
                    isLiveMode: isLiveMode
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )

            } else {
                // Fallback: best-effort render directly if plugin registry can't be resolved.
                // Ensure config exists and keep config.id aligned with module.id.
                let cfg: ProPresenterModuleConfig = {
                    if let modules = tile.modules,
                       let idx = modules.firstIndex(where: { $0.id == module.id }) {
                        var updated = tile
                        var didMutate = false
                        if updated.modules?[idx].proPresenterConfig == nil {
                            var c = ProPresenterModuleConfig()
                            c.id = module.id
                            updated.modules?[idx].proPresenterConfig = c
                            didMutate = true
                        } else if updated.modules?[idx].proPresenterConfig?.id != module.id {
                            updated.modules?[idx].proPresenterConfig?.id = module.id
                            didMutate = true
                        }
                        if didMutate {
                            actions.setTile(tabID: tab.id, tileID: tile.id, to: updated)
                        }
                        return updated.modules?[idx].proPresenterConfig ?? ProPresenterModuleConfig()
                    }
                    var c = ProPresenterModuleConfig()
                    c.id = module.id
                    return c
                }()

                let cfgBinding = Binding<ProPresenterModuleConfig>(
                    get: {
                        // Always return the stored per-module config when possible.
                        if let mods = tile.modules,
                           let i = mods.firstIndex(where: { $0.id == module.id }),
                           let stored = mods[i].proPresenterConfig {
                            return stored
                        }
                        // Fallback to the computed cfg (already has id aligned).
                        return cfg
                    },
                    set: { newValue in
                        // Persist back into the module's stored config.
                        guard var mods = tile.modules,
                              let i = mods.firstIndex(where: { $0.id == module.id }) else {
                            return
                        }
                        var v = newValue
                        v.id = module.id
                        mods[i].proPresenterConfig = v
                        var updated = tile
                        updated.modules = mods
                        actions.setTile(tabID: tab.id, tileID: tile.id, to: updated)
                    }
                )

                ProPresenterModuleView(
                    moduleID: module.id,
                    config: cfgBinding,
                    service: ProPresenterModulePlugin.sharedService,
                    isLiveMode: isLiveMode
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            }

        case .resolume:
            if let plugin = DashboardModuleRegistry.plugin(for: module.kind) {
                let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)

                plugin.tileView(
                    tab: tabBinding,
                    tile: tileBinding,
                    module: moduleBinding,
                    isLiveMode: isLiveMode
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: true
                    )
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    DashboardSymbolLabel("Resolume", preferred: "sparkles.tv")
                        .font(.headline)
                    Text("No Resolume data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: true
                    )
                )
            }

        case .dbReader:
            if let plugin = DashboardModuleRegistry.plugin(for: module.kind) {
                let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)

                plugin.tileView(
                    tab: tabBinding,
                    tile: tileBinding,
                    module: moduleBinding,
                    isLiveMode: isLiveMode
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("SPL Meter", systemImage: "speaker.wave.2.fill")
                        .font(.headline)
                    Text("No meter data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            }

        case .button:
            if let plugin = DashboardModuleRegistry.plugin(for: module.kind) {
                let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)

                plugin.tileView(
                    tab: tabBinding,
                    tile: tileBinding,
                    module: moduleBinding,
                    isLiveMode: isLiveMode
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    DashboardSymbolLabel("Button", preferred: "button.programmable")
                        .font(.headline)
                    Text("No button configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            }

        case .liveTranscription:
            if let plugin = DashboardModuleRegistry.plugin(for: module.kind) {
                let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)

                plugin.tileView(
                    tab: tabBinding,
                    tile: tileBinding,
                    module: moduleBinding,
                    isLiveMode: isLiveMode
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Live Transcription", systemImage: "waveform")
                        .font(.headline)
                    Text("No transcription data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            }

        case .time, .timecode, .dawTransport:
            if let plugin = DashboardModuleRegistry.plugin(for: module.kind) {
                let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)

                plugin.tileView(
                    tab: tabBinding,
                    tile: tileBinding,
                    module: moduleBinding,
                    isLiveMode: isLiveMode
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            } else {
                // Fallback if plugin registry isn't set up yet
                TimeModuleView(
                    config: .constant(TimeModuleConfig.default()),
                    moduleID: module.id,
                    isLiveMode: isLiveMode
                )
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .modifier(
                        ModuleCornerClip(
                            radius: tileCornerRadius,
                            style: style,
                            enabled: shouldClipForStack
                        )
                    )
            }

        case .rosterPicker:
            if let plugin = DashboardModuleRegistry.plugin(for: module.kind) {
                let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)

                plugin.tileView(
                    tab: tabBinding,
                    tile: tileBinding,
                    module: moduleBinding,
                    isLiveMode: isLiveMode
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            } else {
                let model: RosterPickerModuleModel = {
                    if case .rosterPicker(let m) = module.kind {
                        return m
                    }
                    return RosterPickerModuleModel()
                }()

                RosterPickerModuleView(model: model, tab: tab)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .modifier(
                        ModuleCornerClip(
                            radius: tileCornerRadius,
                            style: style,
                            enabled: shouldClipForStack
                        )
                    )
            }

        case .text:
            let constrainedMaxHeight: CGFloat? = {
                guard let maxHeight, maxHeight < DashboardTileMetrics.textModuleNaturalHeight else { return nil }
                return maxHeight
            }()

            if let plugin = DashboardModuleRegistry.plugin(for: module.kind) {
                let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)

                plugin.tileView(
                    tab: tabBinding,
                    tile: tileBinding,
                    module: moduleBinding,
                    isLiveMode: isLiveMode
                )
                .frame(
                    maxWidth: .infinity,
                    maxHeight: constrainedMaxHeight ?? .infinity,
                    alignment: .topLeading
                )
                .clipped()
                .overlay(bottomFadeOverlay(maxHeight: constrainedMaxHeight))
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )

            } else {
                // Fallback: best-effort render if registry/plugin can't be resolved
                let model: TextModuleModel = {
                    if case .text(let m) = module.kind {
                        return m
                    } else {
                        return TextModuleModel()
                    }
                }()
                TextModuleView(model: model)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: constrainedMaxHeight ?? .infinity,
                        alignment: .topLeading
                    )
                    .clipped()
                    .overlay(bottomFadeOverlay(maxHeight: constrainedMaxHeight))
                    .modifier(
                        ModuleCornerClip(
                            radius: tileCornerRadius,
                            style: style,
                            enabled: shouldClipForStack
                        )
                    )
            }
//                .frame(
//                    maxWidth: .infinity,
//                    maxHeight: constrainedMaxHeight ?? .infinity,
//                    alignment: .topLeading
//                )
//                .clipped()
//                .overlay(bottomFadeOverlay(maxHeight: constrainedMaxHeight))
//                .modifier(
//                    ModuleCornerClip(
//                        radius: tileCornerRadius,
//                        style: style,
//                        enabled: shouldClipForStack
//                    )
//                )

        case .document:
            if let plugin = DashboardModuleRegistry.plugin(for: module.kind) {
                let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)

                plugin.tileView(
                    tab: tabBinding,
                    tile: tileBinding,
                    module: moduleBinding,
                    isLiveMode: isLiveMode
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            } else {
                let model: DocumentModuleModel = {
                    if case .document(let m) = module.kind {
                        return m
                    } else {
                        return DocumentModuleModel()
                    }
                }()
                DocumentModuleView(model: model)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .modifier(
                        ModuleCornerClip(
                            radius: tileCornerRadius,
                            style: style,
                            enabled: shouldClipForStack
                        )
                    )
            }

        case .image:
            if let plugin = DashboardModuleRegistry.plugin(for: module.kind) {
                let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)

                plugin.tileView(
                    tab: tabBinding,
                    tile: tileBinding,
                    module: moduleBinding,
                    isLiveMode: isLiveMode
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            } else {
                let model: ImageModuleModel = {
                    if case .image(let m) = module.kind {
                        return m
                    } else {
                        return ImageModuleModel()
                    }
                }()
                ImageModuleView(model: model)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .modifier(
                        ModuleCornerClip(
                            radius: tileCornerRadius,
                            style: style,
                            enabled: shouldClipForStack
                        )
                    )
            }

        case .ndi:
            if let plugin = DashboardModuleRegistry.plugin(for: module.kind) {
                let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)

                plugin.tileView(
                    tab: tabBinding,
                    tile: tileBinding,
                    module: moduleBinding,
                    isLiveMode: isLiveMode
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            }

        case .webpage:
            if let plugin = DashboardModuleRegistry.plugin(for: module.kind) {
                let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)

                plugin.tileView(
                    tab: tabBinding,
                    tile: tileBinding,
                    module: moduleBinding,
                    isLiveMode: isLiveMode
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            } else {
                let model: WebpageModuleModel = {
                    if case .webpage(let m) = module.kind {
                        return m
                    }
                    return WebpageModuleModel()
                }()

                WebpageModuleView(model: .constant(model), isLiveMode: isLiveMode)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .modifier(
                        ModuleCornerClip(
                            radius: tileCornerRadius,
                            style: style,
                            enabled: shouldClipForStack
                        )
                    )
            }

        case .youtubeStreamMonitor:
            if let plugin = DashboardModuleRegistry.plugin(for: module.kind) {
                let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)

                plugin.tileView(
                    tab: tabBinding,
                    tile: tileBinding,
                    module: moduleBinding,
                    isLiveMode: isLiveMode
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            }

        case .rta, .spectrograph:
            if let plugin = DashboardModuleRegistry.plugin(for: module.kind) {
                let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)
                plugin.tileView(
                    tab: tabBinding,
                    tile: tileBinding,
                    module: moduleBinding,
                    isLiveMode: isLiveMode
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            }

        case .separator:
            let moduleBinding = DashboardTileModuleBinding.binding(for: module, tile: tileBinding)

            if let plugin = DashboardModuleRegistry.plugin(for: moduleBinding.wrappedValue.kind) {
                plugin.tileView(
                    tab: tabBinding,
                    tile: tileBinding,
                    module: moduleBinding,
                    isLiveMode: isLiveMode
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .modifier(
                    ModuleCornerClip(
                        radius: tileCornerRadius,
                        style: style,
                        enabled: shouldClipForStack
                    )
                )
            } else {
                // Fallback: still read from the live binding so style/thickness changes redraw.
                let model: SeparatorModuleModel = {
                    if case .separator(let m) = moduleBinding.wrappedValue.kind {
                        return m
                    }
                    return SeparatorModuleModel()
                }()

                SeparatorModuleView(model: model, moduleLayout: tile.moduleLayout)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .modifier(
                        ModuleCornerClip(
                            radius: tileCornerRadius,
                            style: style,
                            enabled: shouldClipForStack
                        )
                    )
            }

        }
            }
            .simultaneousGesture(
                TapGesture().onEnded { actions.recordInteractiveTileTap() },
                including: isLiveMode ? .all : .none
            )
            .allowsHitTesting(liveModeInteractionAllowed)
        }

    }
    // MARK: - Tile Commands

    /// Aligns all *selected* tiles in the current tab so their origins land on the nearest
    /// grid intersection, using the current grid size. Has no effect if the grid size is
    /// zero or negative.
    private func alignSelectedTilesToGrid() {
        guard gridSize > 0 else { return }

        var updatedTab = tab
        for idx in updatedTab.tiles.indices {
            let id = updatedTab.tiles[idx].id
            guard selectedTileIDs.contains(id) else { continue }

            var t = updatedTab.tiles[idx]
            let x = t.offset.width
            let y = t.offset.height

            let snappedX = (x / gridSize).rounded() * gridSize
            let snappedY = (y / gridSize).rounded() * gridSize

            t.offset.width = snappedX
            t.offset.height = snappedY
            updatedTab.tiles[idx] = t
        }
        actions.setTab(updatedTab)

        actions.persist(reconcileGraphNodes: false)
    }
    private func distributeSpacingHorizontally() {
        let selectedIDs = selectedTileIDs
        guard selectedIDs.count >= 2 else { return }

        var updatedTab = tab
        let indices = updatedTab.tiles.indices.filter { selectedIDs.contains(updatedTab.tiles[$0].id) }
        guard indices.count >= 2 else { return }

        let sortedIndices = indices.sorted { updatedTab.tiles[$0].offset.width < updatedTab.tiles[$1].offset.width }

        let firstIndex = sortedIndices[0]
        let firstTile = updatedTab.tiles[firstIndex]
        let baseHeight = firstTile.offset.height

        var currentX = firstTile.offset.width
        let gap: CGFloat = 0

        for idx in sortedIndices {
            var t = updatedTab.tiles[idx]
            t.offset.width = currentX
            t.offset.height = baseHeight
            updatedTab.tiles[idx] = t

            let size = DashboardTileSnappingHelper.effectiveSize(for: t, defaultTileSize: defaultTileSize)
            currentX += size.width + gap
        }
        actions.setTab(updatedTab)

        actions.persist(reconcileGraphNodes: false)
    }

    private func distributeSpacingVertically() {
        let selectedIDs = selectedTileIDs
        guard selectedIDs.count >= 2 else { return }

        var updatedTab = tab
        let indices = updatedTab.tiles.indices.filter { selectedIDs.contains(updatedTab.tiles[$0].id) }
        guard indices.count >= 2 else { return }

        let sortedIndices = indices.sorted { updatedTab.tiles[$0].offset.height < updatedTab.tiles[$1].offset.height }

        let firstIndex = sortedIndices[0]
        let firstTile = updatedTab.tiles[firstIndex]
        let baseWidth = firstTile.offset.width

        var currentY = firstTile.offset.height
        let gap: CGFloat = 0

        for idx in sortedIndices {
            var t = updatedTab.tiles[idx]
            t.offset.height = currentY
            t.offset.width = baseWidth
            updatedTab.tiles[idx] = t

            let size = DashboardTileSnappingHelper.effectiveSize(for: t, defaultTileSize: defaultTileSize)
            currentY += size.height + gap
        }
        actions.setTab(updatedTab)

        actions.persist(reconcileGraphNodes: false)
    }

    /// Resolves overlaps by snapping tiles to the nearest available grid position.
    /// If there is a selection, only selected (visible) tiles are moved. Otherwise,
    /// all visible tiles are considered. Hidden tiles are ignored.
    private func resolveTileOverlapsToGrid() {
        guard gridSize > 0 else { return }

        var updatedTab = tab
        let visibleTiles = updatedTab.tiles.filter { !$0.isHidden }
        guard !visibleTiles.isEmpty else { return }

        let selectedIDs = selectedTileIDs
        let targetIDs: Set<UUID> = selectedIDs.isEmpty
            ? Set(visibleTiles.map(\.id))
            : selectedIDs

        guard !targetIDs.isEmpty else { return }

        func rectFor(tile: DashboardTileModel, offset: CGSize? = nil) -> CGRect {
            let size = DashboardTileSnappingHelper.effectiveSize(for: tile, defaultTileSize: defaultTileSize)
            let origin = offset ?? tile.offset
            return CGRect(x: origin.width, y: origin.height, width: size.width, height: size.height)
        }

        var occupiedRects: [CGRect] = []
        for tile in updatedTab.tiles where !tile.isHidden && !targetIDs.contains(tile.id) {
            occupiedRects.append(rectFor(tile: tile))
        }

        let canvasWidth = canvasSize.width > 0 ? canvasSize.width : 1200
        let canvasHeight = canvasSize.height > 0 ? canvasSize.height : 800
        let maxRadius = Int(ceil(max(canvasWidth, canvasHeight) / gridSize)) + 2

        func findNearestFreeOffset(
            baseOffset: CGSize,
            size: CGSize
        ) -> CGSize {
            let maxX = max(0, canvasWidth - size.width)
            let maxY = max(0, canvasHeight - size.height)

            func clamped(_ offset: CGSize) -> CGSize {
                CGSize(
                    width: min(max(offset.width, 0), maxX),
                    height: min(max(offset.height, 0), maxY)
                )
            }

            func fits(_ offset: CGSize) -> Bool {
                let rect = CGRect(x: offset.width, y: offset.height, width: size.width, height: size.height)
                return !occupiedRects.contains { $0.intersects(rect) }
            }

            let snappedBase = CGSize(
                width: (baseOffset.width / gridSize).rounded() * gridSize,
                height: (baseOffset.height / gridSize).rounded() * gridSize
            )
            let start = clamped(snappedBase)
            if fits(start) { return start }

            for radius in 1...maxRadius {
                for dx in -radius...radius {
                    for dy in -radius...radius {
                        if max(abs(dx), abs(dy)) != radius { continue }
                        let candidate = CGSize(
                            width: start.width + CGFloat(dx) * gridSize,
                            height: start.height + CGFloat(dy) * gridSize
                        )
                        let clampedCandidate = clamped(candidate)
                        if fits(clampedCandidate) {
                            return clampedCandidate
                        }
                    }
                }
            }

            return start
        }

        var didPushUndo = false

        for index in updatedTab.tiles.indices {
            var tile = updatedTab.tiles[index]
            guard !tile.isHidden, targetIDs.contains(tile.id) else { continue }

            let size = DashboardTileSnappingHelper.effectiveSize(for: tile, defaultTileSize: defaultTileSize)
            let newOffset = findNearestFreeOffset(baseOffset: tile.offset, size: size)

            if newOffset != tile.offset {
                if !didPushUndo {
                    actions.undoSnapshot("Resolve Tile Overlaps")
                    didPushUndo = true
                }

                tile.offset = newOffset
                updatedTab.tiles[index] = tile
            }

            occupiedRects.append(rectFor(tile: tile, offset: newOffset))
        }
        actions.setTab(updatedTab)

        actions.persist(reconcileGraphNodes: false)
    }
}
