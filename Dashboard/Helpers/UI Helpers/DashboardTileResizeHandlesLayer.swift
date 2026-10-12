import SwiftUI

struct DashboardTileResizeHandlesLayer: View {
    let size: CGSize
    let tileSize: CGSize?
    let defaultSize: CGSize
    let isLiveMode: Bool
    let isSelected: Bool
    let isGroupResizeMode: Bool
    let draggingDisabled: Bool
    let tileOffset: CGSize
    let guides: [CanvasGuide]
    let canvasSize: CGSize
    let showGuidesEnabled: Bool
    let snapToGrid: Bool
    let gridSize: CGFloat
    let viewportZoom: CGFloat
    let otherTileRects: [CGRect]
    let interactionSession: DashboardTileInteractionSession
    let onResizeBegan: () -> Void
    let onResizeEnded: () -> Void
    /// Fires once per drag-changed event with the combined size/offset
    /// result for whichever handle is being dragged. Passed unchanged to
    /// every `ResizeHandle` below -- each handle's orientation already
    /// determines (via `DashboardResizeSnappingHelper.computeResize`)
    /// whether `newOffsetY`/`newOffsetX` come back non-nil, so no
    /// per-handle closure wiring is needed. See `ResizeHandle.onResizeChanged`.
    let onResizeChanged: (_ size: CGSize, _ newOffsetY: CGFloat?, _ newOffsetX: CGFloat?) -> Void

    private var showsIndicator: Bool {
        isSelected && !isLiveMode
    }

    @State private var dragState = ResizeHandleDragState()

    var body: some View {
        if !isLiveMode {
            let layout = DashboardTileResizeHandleLayout(size: size)
            let halo = DashboardTileResizeHandleLayout.hitHalo

            let bottomRightHandle = ResizeHandle(
                size: tileSize,
                defaultSize: defaultSize,
                onResizeBegan: onResizeBegan,
                onResizeEnded: onResizeEnded,
                orientation: .diagonal,
                tileOffset: tileOffset,
                guides: guides,
                canvasSize: canvasSize,
                showGuidesEnabled: showGuidesEnabled,
                snapToGrid: snapToGrid,
                gridSize: gridSize,
                viewportZoom: viewportZoom,
                otherTileRects: otherTileRects,
                interactionSession: interactionSession,
                onResizeChanged: onResizeChanged,
                showsIndicator: showsIndicator,
                isEnabled: !draggingDisabled,
                dragState: dragState
            )

            let topRightHandle = ResizeHandle(
                size: tileSize,
                defaultSize: defaultSize,
                onResizeBegan: onResizeBegan,
                onResizeEnded: onResizeEnded,
                orientation: .diagonalTopRight,
                tileOffset: tileOffset,
                guides: guides,
                canvasSize: canvasSize,
                showGuidesEnabled: showGuidesEnabled,
                snapToGrid: snapToGrid,
                gridSize: gridSize,
                viewportZoom: viewportZoom,
                otherTileRects: otherTileRects,
                interactionSession: interactionSession,
                onResizeChanged: onResizeChanged,
                showsIndicator: showsIndicator,
                isEnabled: !draggingDisabled,
                dragState: dragState
            )

            let topLeftHandle = ResizeHandle(
                size: tileSize,
                defaultSize: defaultSize,
                onResizeBegan: onResizeBegan,
                onResizeEnded: onResizeEnded,
                orientation: .diagonalTopLeft,
                tileOffset: tileOffset,
                guides: guides,
                canvasSize: canvasSize,
                showGuidesEnabled: showGuidesEnabled,
                snapToGrid: snapToGrid,
                gridSize: gridSize,
                viewportZoom: viewportZoom,
                otherTileRects: otherTileRects,
                interactionSession: interactionSession,
                onResizeChanged: onResizeChanged,
                showsIndicator: showsIndicator,
                isEnabled: !draggingDisabled,
                dragState: dragState
            )

            let leftEdgeHandle = ResizeHandle(
                size: tileSize,
                defaultSize: defaultSize,
                onResizeBegan: onResizeBegan,
                onResizeEnded: onResizeEnded,
                orientation: .horizontalLeft,
                tileOffset: tileOffset,
                guides: guides,
                canvasSize: canvasSize,
                showGuidesEnabled: showGuidesEnabled,
                snapToGrid: snapToGrid,
                gridSize: gridSize,
                viewportZoom: viewportZoom,
                otherTileRects: otherTileRects,
                interactionSession: interactionSession,
                onResizeChanged: onResizeChanged,
                showsIndicator: showsIndicator,
                isEnabled: !draggingDisabled,
                dragState: dragState
            )

            let bottomLeftHandle = ResizeHandle(
                size: tileSize,
                defaultSize: defaultSize,
                onResizeBegan: onResizeBegan,
                onResizeEnded: onResizeEnded,
                orientation: .diagonalBottomLeft,
                tileOffset: tileOffset,
                guides: guides,
                canvasSize: canvasSize,
                showGuidesEnabled: showGuidesEnabled,
                snapToGrid: snapToGrid,
                gridSize: gridSize,
                viewportZoom: viewportZoom,
                otherTileRects: otherTileRects,
                interactionSession: interactionSession,
                onResizeChanged: onResizeChanged,
                showsIndicator: showsIndicator,
                isEnabled: !draggingDisabled,
                dragState: dragState
            )

            let rightEdgeHandle = ResizeHandle(
                size: tileSize,
                defaultSize: defaultSize,
                onResizeBegan: onResizeBegan,
                onResizeEnded: onResizeEnded,
                orientation: .horizontal,
                tileOffset: tileOffset,
                guides: guides,
                canvasSize: canvasSize,
                showGuidesEnabled: showGuidesEnabled,
                snapToGrid: snapToGrid,
                gridSize: gridSize,
                viewportZoom: viewportZoom,
                otherTileRects: otherTileRects,
                interactionSession: interactionSession,
                onResizeChanged: onResizeChanged,
                showsIndicator: showsIndicator,
                isEnabled: !draggingDisabled,
                dragState: dragState
            )

            let bottomEdgeHandle = ResizeHandle(
                size: tileSize,
                defaultSize: defaultSize,
                onResizeBegan: onResizeBegan,
                onResizeEnded: onResizeEnded,
                orientation: .vertical,
                tileOffset: tileOffset,
                guides: guides,
                canvasSize: canvasSize,
                showGuidesEnabled: showGuidesEnabled,
                snapToGrid: snapToGrid,
                gridSize: gridSize,
                viewportZoom: viewportZoom,
                otherTileRects: otherTileRects,
                interactionSession: interactionSession,
                onResizeChanged: onResizeChanged,
                showsIndicator: showsIndicator,
                isEnabled: !draggingDisabled,
                dragState: dragState
            )

            let topEdgeHandle = ResizeHandle(
                size: tileSize,
                defaultSize: defaultSize,
                onResizeBegan: onResizeBegan,
                onResizeEnded: onResizeEnded,
                orientation: .verticalTop,
                tileOffset: tileOffset,
                guides: guides,
                canvasSize: canvasSize,
                showGuidesEnabled: showGuidesEnabled,
                snapToGrid: snapToGrid,
                gridSize: gridSize,
                viewportZoom: viewportZoom,
                otherTileRects: otherTileRects,
                interactionSession: interactionSession,
                onResizeChanged: onResizeChanged,
                showsIndicator: showsIndicator,
                isEnabled: !draggingDisabled,
                dragState: dragState
            )

            ZStack {
                if !isGroupResizeMode {
                    bottomRightHandle
                        .position(x: layout.bottomRight.x + halo, y: layout.bottomRight.y + halo)
                    topRightHandle
                        .position(x: layout.topRight.x + halo, y: layout.topRight.y + halo)
                    topLeftHandle
                        .position(x: layout.topLeft.x + halo, y: layout.topLeft.y + halo)
                    leftEdgeHandle
                        .position(x: layout.leftEdge.x + halo, y: layout.leftEdge.y + halo)
                    bottomLeftHandle
                        .position(x: layout.bottomLeft.x + halo, y: layout.bottomLeft.y + halo)
                    rightEdgeHandle
                        .position(x: layout.rightEdge.x + halo, y: layout.rightEdge.y + halo)
                }

                bottomEdgeHandle
                    .position(x: layout.bottomEdge.x + halo, y: layout.bottomEdge.y + halo)
                topEdgeHandle
                    .position(x: layout.topEdge.x + halo, y: layout.topEdge.y + halo)

                #if os(macOS)
                DashboardResizeInteractionSurface(
                    size: size,
                    halo: halo,
                    isEnabled: !draggingDisabled,
                    allowedOrientations: isGroupResizeMode ? [.vertical, .verticalTop] : nil,
                    controllers: [
                        .diagonal: bottomRightHandle.controller,
                        .diagonalTopRight: topRightHandle.controller,
                        .diagonalTopLeft: topLeftHandle.controller,
                        .horizontalLeft: leftEdgeHandle.controller,
                        .diagonalBottomLeft: bottomLeftHandle.controller,
                        .horizontal: rightEdgeHandle.controller,
                        .vertical: bottomEdgeHandle.controller,
                        .verticalTop: topEdgeHandle.controller
                    ]
                )
                .allowsHitTesting(!draggingDisabled)
                #endif
            }
            .frame(width: size.width + halo * 2, height: size.height + halo * 2)
        }
    }
}
