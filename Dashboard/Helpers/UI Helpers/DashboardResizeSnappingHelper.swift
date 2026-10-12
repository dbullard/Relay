//
//  DashboardResizeSnappingHelper.swift
//  Relay
//
//  Extracted from ResizeHandle gesture logic in DashboardRootView.swift
//  to keep the root file smaller and make resizing/snapping behavior testable.
//

import SwiftUI

enum DashboardResizeSnappingHelper {

    struct ResizeResult {
        var size: CGSize
        /// If non-nil, caller should update tile's X offset (left-edge resizing).
        var newOffsetX: CGFloat?
        /// If non-nil, caller should update tile's Y offset (top-edge resizing).
        var newOffsetY: CGFloat?
        /// Smart guides active during this resize frame
        var activeGuides: [SmartGuideLine]
    }

    static func computeResize(
        baseSize: CGSize,
        startLocation: CGPoint,
        currentLocation: CGPoint,
        orientation: ResizeHandleOrientation,
        tileOffset: CGSize,
        guides: [CanvasGuide],
        canvasSize: CGSize,
        showGuidesEnabled: Bool,
        snapToGrid: Bool,
        gridSize: CGFloat,
        isShiftDown: Bool,
        dragStartBottom: CGFloat?,
        dragStartRight: CGFloat?,
        otherTileRects: [CGRect] = [],
        minWidth: CGFloat = 44,
        minHeight: CGFloat = 44
    ) -> ResizeResult {

        let dx = currentLocation.x - startLocation.x
        let dy = currentLocation.y - startLocation.y

        var rawWidth: CGFloat
        var rawHeight: CGFloat

        switch orientation {
        case .horizontal:
            rawWidth = baseSize.width + dx
            rawHeight = baseSize.height
        case .horizontalLeft:
            rawWidth = baseSize.width - dx
            rawHeight = baseSize.height
        case .vertical:
            rawWidth = baseSize.width
            rawHeight = baseSize.height + dy
        case .verticalTop:
            rawWidth = baseSize.width
            rawHeight = baseSize.height - dy
        case .diagonal:
            rawWidth = baseSize.width + dx
            rawHeight = baseSize.height + dy
        case .diagonalTopRight:
            rawWidth = baseSize.width + dx
            rawHeight = baseSize.height - dy
        case .diagonalTopLeft:
            rawWidth = baseSize.width - dx
            rawHeight = baseSize.height - dy
        case .diagonalBottomLeft:
            rawWidth = baseSize.width - dx
            rawHeight = baseSize.height + dy
        }

        var activeGuides: [SmartGuideLine] = []

        // Optional snapping to guides / canvas edges / tiles when Shift is held,
        // similar to tile movement snapping.
        if isShiftDown, showGuidesEnabled {
            let snapThreshold: CGFloat = 30

            let left = tileOffset.width
            let top = tileOffset.height

            // Right-edge snapping for handles that move the right edge.
            if orientation == .horizontal || orientation == .diagonal || orientation == .diagonalTopRight {
                let proposedRight = left + rawWidth
                var bestRight = proposedRight
                var bestDX = snapThreshold

                for guide in guides where guide.orientation == .vertical {
                    let gx = guide.position
                    let dxGuide = abs(gx - proposedRight)
                    if dxGuide < bestDX {
                        bestDX = dxGuide
                        bestRight = gx
                    }
                }

                for rect in otherTileRects {
                    let edges = [rect.minX, rect.maxX]
                    for ex in edges {
                        let dxTile = abs(ex - proposedRight)
                        if dxTile < bestDX {
                            bestDX = dxTile
                            bestRight = ex
                        }
                    }
                }

                if canvasSize.width > 0 {
                    let rightCanvas = canvasSize.width
                    let dxCanvas = abs(rightCanvas - proposedRight)
                    if dxCanvas < bestDX {
                        bestDX = dxCanvas
                        bestRight = rightCanvas
                    }

                    let centerCanvas = canvasSize.width / 2
                    let proposedCenter = left + rawWidth / 2
                    let dxCenter = abs(centerCanvas - proposedCenter)
                    if dxCenter < bestDX {
                        bestDX = dxCenter
                        // If we snap center, the new right edge is such that the center is at centerCanvas.
                        // center = left + rawWidth / 2 => rawWidth = 2 * (center - left)
                        // bestRight = left + rawWidth => bestRight = left + 2 * (centerCanvas - left) = 2 * centerCanvas - left
                        bestRight = 2 * centerCanvas - left
                    }
                }

                if bestDX < snapThreshold {
                    rawWidth = bestRight - left
                    activeGuides.append(SmartGuideLine(orientation: .vertical, position: bestRight == (2 * (canvasSize.width / 2) - left) ? (canvasSize.width / 2) : bestRight))
                }
            }

            // Left-edge snapping for handles that move the left edge.
            if orientation == .horizontalLeft || orientation == .diagonalTopLeft || orientation == .diagonalBottomLeft {
                let proposedLeft = left + dx
                var bestLeft = proposedLeft
                var bestDX = snapThreshold

                for guide in guides where guide.orientation == .vertical {
                    let gx = guide.position
                    let dxGuide = abs(gx - proposedLeft)
                    if dxGuide < bestDX {
                        bestDX = dxGuide
                        bestLeft = gx
                    }
                }

                for rect in otherTileRects {
                    let edges = [rect.minX, rect.maxX]
                    for ex in edges {
                        let dxTile = abs(ex - proposedLeft)
                        if dxTile < bestDX {
                            bestDX = dxTile
                            bestLeft = ex
                        }
                    }
                }

                let leftCanvas: CGFloat = 0
                let dxCanvas = abs(leftCanvas - proposedLeft)
                if dxCanvas < bestDX {
                    bestDX = dxCanvas
                    bestLeft = leftCanvas
                }

                if canvasSize.width > 0 {
                    let right = dragStartRight ?? (tileOffset.width + baseSize.width)
                    let centerCanvas = canvasSize.width / 2
                    let proposedCenter = proposedLeft + (right - proposedLeft) / 2
                    let dxCenter = abs(centerCanvas - proposedCenter)
                    if dxCenter < bestDX {
                        bestDX = dxCenter
                        // center = left + (right - left) / 2 => 2*center = left + right => left = 2*center - right
                        bestLeft = 2 * centerCanvas - right
                    }
                }

                if bestDX < snapThreshold {
                    let right = dragStartRight ?? (tileOffset.width + baseSize.width)
                    rawWidth = right - bestLeft
                    let isCenterSnap = canvasSize.width > 0 && bestLeft == (2 * (canvasSize.width / 2) - right)
                    activeGuides.append(SmartGuideLine(orientation: .vertical, position: isCenterSnap ? (canvasSize.width / 2) : bestLeft))
                }
            }

            // Bottom-edge snapping
            if orientation == .vertical || orientation == .diagonal || orientation == .diagonalBottomLeft {
                let proposedBottom = top + rawHeight
                var bestBottom = proposedBottom
                var bestDY = snapThreshold

                for guide in guides where guide.orientation == .horizontal {
                    let gy = guide.position
                    let dyGuide = abs(gy - proposedBottom)
                    if dyGuide < bestDY {
                        bestDY = dyGuide
                        bestBottom = gy
                    }
                }

                for rect in otherTileRects {
                    let edges = [rect.minY, rect.maxY]
                    for ey in edges {
                        let dyTile = abs(ey - proposedBottom)
                        if dyTile < bestDY {
                            bestDY = dyTile
                            bestBottom = ey
                        }
                    }
                }

                if canvasSize.height > 0 {
                    let bottomCanvas = canvasSize.height
                    let dyCanvas = abs(bottomCanvas - proposedBottom)
                    if dyCanvas < bestDY {
                        bestDY = dyCanvas
                        bestBottom = bottomCanvas
                    }

                    let centerCanvas = canvasSize.height / 2
                    let proposedCenter = top + rawHeight / 2
                    let dyCenter = abs(centerCanvas - proposedCenter)
                    if dyCenter < bestDY {
                        bestDY = dyCenter
                        // center = top + rawHeight / 2 => rawHeight = 2 * (center - top)
                        // bestBottom = top + rawHeight => bestBottom = 2 * centerCanvas - top
                        bestBottom = 2 * centerCanvas - top
                    }
                }

                if bestDY < snapThreshold {
                    rawHeight = bestBottom - top
                    let isCenterSnap = canvasSize.height > 0 && bestBottom == (2 * (canvasSize.height / 2) - top)
                    activeGuides.append(SmartGuideLine(orientation: .horizontal, position: isCenterSnap ? (canvasSize.height / 2) : bestBottom))
                }
            }
            // Top-edge snapping
            else if orientation == .verticalTop || orientation == .diagonalTopRight || orientation == .diagonalTopLeft {
                let proposedTop = top + dy
                var bestTop = proposedTop
                var bestDY = snapThreshold

                for guide in guides where guide.orientation == .horizontal {
                    let gy = guide.position
                    let dyGuide = abs(gy - proposedTop)
                    if dyGuide < bestDY {
                        bestDY = dyGuide
                        bestTop = gy
                    }
                }

                for rect in otherTileRects {
                    let edges = [rect.minY, rect.maxY]
                    for ey in edges {
                        let dyTile = abs(ey - proposedTop)
                        if dyTile < bestDY {
                            bestDY = dyTile
                            bestTop = ey
                        }
                    }
                }

                let topCanvas: CGFloat = 0
                let dyCanvas = abs(topCanvas - proposedTop)
                if dyCanvas < bestDY {
                    bestDY = dyCanvas
                    bestTop = topCanvas
                }

                if canvasSize.height > 0 {
                    let bottom = dragStartBottom ?? (tileOffset.height + baseSize.height)
                    let centerCanvas = canvasSize.height / 2
                    let proposedCenter = proposedTop + (bottom - proposedTop) / 2
                    let dyCenter = abs(centerCanvas - proposedCenter)
                    if dyCenter < bestDY {
                        bestDY = dyCenter
                        // center = top + (bottom - top) / 2 => 2*center = top + bottom => top = 2*center - bottom
                        bestTop = 2 * centerCanvas - bottom
                    }
                }

                if bestDY < snapThreshold {
                    let bottom = dragStartBottom ?? (tileOffset.height + baseSize.height)
                    rawHeight = bottom - bestTop
                    let isCenterSnap = canvasSize.height > 0 && bestTop == (2 * (canvasSize.height / 2) - bottom)
                    activeGuides.append(SmartGuideLine(orientation: .horizontal, position: isCenterSnap ? (canvasSize.height / 2) : bestTop))
                }
            }
        }

        var newWidth = max(minWidth, rawWidth)
        var newHeight = max(minHeight, rawHeight)

        // Grid snapping for resize dimensions.
        if isShiftDown, gridSize > 0, activeGuides.isEmpty {
            func snapDim(_ v: CGFloat) -> CGFloat { (v / gridSize).rounded() * gridSize }

            switch orientation {
            case .horizontal, .horizontalLeft:
                newWidth = max(minWidth, snapDim(newWidth))
            case .vertical, .verticalTop:
                newHeight = max(minHeight, snapDim(newHeight))
            case .diagonal, .diagonalTopRight, .diagonalTopLeft, .diagonalBottomLeft:
                newWidth = max(minWidth, snapDim(newWidth))
                newHeight = max(minHeight, snapDim(newHeight))
            }
        }

        var result = ResizeResult(size: CGSize(width: newWidth, height: newHeight), newOffsetX: nil, newOffsetY: nil, activeGuides: activeGuides)

        // Offset adjustments for top-edge resizing (keep bottom anchored).
        if orientation == .verticalTop || orientation == .diagonalTopRight || orientation == .diagonalTopLeft {
            let bottom = dragStartBottom ?? (tileOffset.height + baseSize.height)
            let unclampedTop = bottom - newHeight

            if canvasSize.height > 0 {
                let maxTop = max(0, canvasSize.height - newHeight)
                let clampedTop = min(max(unclampedTop, 0), maxTop)
                result.newOffsetY = clampedTop
            } else {
                result.newOffsetY = unclampedTop
            }
        }

        // Offset adjustments for left-edge resizing (keep right anchored).
        if orientation == .horizontalLeft || orientation == .diagonalTopLeft || orientation == .diagonalBottomLeft {
            let right = dragStartRight ?? (tileOffset.width + baseSize.width)
            let unclampedLeft = right - newWidth

            if canvasSize.width > 0 {
                let maxLeft = max(0, canvasSize.width - newWidth)
                let clampedLeft = min(max(unclampedLeft, 0), maxLeft)
                result.newOffsetX = clampedLeft
            } else {
                result.newOffsetX = unclampedLeft
            }
        }

        return result
    }
}
