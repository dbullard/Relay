//
//  DashboardTileSnappingHelper.swift
//  Relay
//
//  Pure helpers extracted from DashboardRootView.DashboardTileContainer snapping logic
//  to keep DashboardRootView.swift smaller.
//

import SwiftUI

enum DashboardTileSnappingHelper {

    /// Computes an effective size for a tile used for snapping math.
    /// Mirrors the tile container's “simple” sizing rules (min size + explicit size or default).
    static func effectiveSize(for tile: DashboardTileModel, defaultTileSize: CGSize) -> CGSize {
        let minWidth: CGFloat = 160
        let minHeight: CGFloat = 120

        let baseWidth = tile.size?.width ?? defaultTileSize.width
        let width = max(minWidth, baseWidth)

        let baseHeight = tile.size?.height ?? defaultTileSize.height
        let height = max(minHeight, baseHeight)

        return CGSize(width: width, height: height)
    }

    /// Given a proposed offset for the current tile, returns a new offset that is
    /// snapped to the nearest neighboring tile edges if they are within a small
    /// distance threshold.
    static func snapOffsetToNearbyTiles(
        proposedOffset: CGSize,
        currentTileID: UUID,
        in tab: DashboardTab,
        canvasSize: CGSize,
        defaultTileSize: CGSize,
        threshold: CGFloat = 10
    ) -> (offset: CGSize, activeGuides: [SmartGuideLine]) {

        let currentSize: CGSize
        if let selfTile = tab.tiles.first(where: { $0.id == currentTileID }) {
            currentSize = effectiveSize(for: selfTile, defaultTileSize: defaultTileSize)
        } else {
            currentSize = defaultTileSize
        }

        // Current rect for the tile being dragged.
        let currentRect = CGRect(
            x: proposedOffset.width,
            y: proposedOffset.height,
            width: currentSize.width,
            height: currentSize.height
        )

        var bestOffset = proposedOffset
        var bestXDistance = threshold + 0.0001
        var bestYDistance = threshold + 0.0001
        var bestXDelta: CGFloat = 0
        var bestYDelta: CGFloat = 0
        var bestCornerScore = threshold + 0.0001
        var bestCornerDelta: CGSize = .zero
        var bestXTarget: CGFloat?
        var bestYTarget: CGFloat?

        for other in tab.tiles where other.id != currentTileID {
            let otherSize = effectiveSize(for: other, defaultTileSize: defaultTileSize)
            let otherRect = CGRect(
                x: other.offset.width,
                y: other.offset.height,
                width: otherSize.width,
                height: otherSize.height
            )

            // Candidate deltas for aligning edges on the X axis.
            let xDeltas: [CGFloat] = [
                otherRect.minX - currentRect.minX,
                otherRect.maxX - currentRect.minX,
                otherRect.minX - currentRect.maxX,
                otherRect.maxX - currentRect.maxX
            ]

            for (dx, targetX) in zip(xDeltas, [otherRect.minX, otherRect.maxX, otherRect.minX, otherRect.maxX]) {
                let distance = abs(dx)
                if distance < bestXDistance {
                    bestXDistance = distance
                    bestXDelta = dx
                    bestXTarget = targetX
                }
            }

            // Candidate deltas for aligning edges on the Y axis.
            let yDeltas: [CGFloat] = [
                otherRect.minY - currentRect.minY,
                otherRect.maxY - currentRect.minY,
                otherRect.minY - currentRect.maxY,
                otherRect.maxY - currentRect.maxY
            ]

            for (dy, targetY) in zip(yDeltas, [otherRect.minY, otherRect.maxY, otherRect.minY, otherRect.maxY]) {
                let distance = abs(dy)
                if distance < bestYDistance {
                    bestYDistance = distance
                    bestYDelta = dy
                    bestYTarget = targetY
                }
            }

            // Candidate delta for center-center snapping
            let centerXDelta = otherRect.midX - currentRect.midX
            if abs(centerXDelta) < bestXDistance {
                bestXDistance = abs(centerXDelta)
                bestXDelta = centerXDelta
                bestXTarget = otherRect.midX
            }

            let centerYDelta = otherRect.midY - currentRect.midY
            if abs(centerYDelta) < bestYDistance {
                bestYDistance = abs(centerYDelta)
                bestYDelta = centerYDelta
                bestYTarget = otherRect.midY
            }

            // Corner snap: combine X + Y deltas from the same target tile.
            for (dx, targetX) in zip(xDeltas, [otherRect.minX, otherRect.maxX, otherRect.minX, otherRect.maxX]) {
                for (dy, targetY) in zip(yDeltas, [otherRect.minY, otherRect.maxY, otherRect.minY, otherRect.maxY]) {
                    let dxAbs = abs(dx)
                    let dyAbs = abs(dy)
                    guard dxAbs <= threshold, dyAbs <= threshold else { continue }
                    let score = max(dxAbs, dyAbs)
                    if score < bestCornerScore {
                        bestCornerScore = score
                        bestCornerDelta = CGSize(width: dx, height: dy)
                        bestXTarget = targetX
                        bestYTarget = targetY
                    }
                }
            }
        }

        // Check center of canvas
        if canvasSize.width > 0 && canvasSize.height > 0 {
            let canvasCenterX = canvasSize.width / 2
            let canvasCenterY = canvasSize.height / 2
            
            let canvasCenterXDelta = canvasCenterX - currentRect.midX
            if abs(canvasCenterXDelta) < bestXDistance {
                bestXDistance = abs(canvasCenterXDelta)
                bestXDelta = canvasCenterXDelta
                bestXTarget = canvasCenterX
            }

            let canvasCenterYDelta = canvasCenterY - currentRect.midY
            if abs(canvasCenterYDelta) < bestYDistance {
                bestYDistance = abs(canvasCenterYDelta)
                bestYDelta = canvasCenterYDelta
                bestYTarget = canvasCenterY
            }
        }

        var activeGuides: [SmartGuideLine] = []

        if bestCornerScore <= threshold {
            bestOffset.width += bestCornerDelta.width
            bestOffset.height += bestCornerDelta.height
            if let x = bestXTarget { activeGuides.append(SmartGuideLine(orientation: .vertical, position: x)) }
            if let y = bestYTarget { activeGuides.append(SmartGuideLine(orientation: .horizontal, position: y)) }
        } else {
            if bestXDistance <= threshold {
                bestOffset.width += bestXDelta
                if let x = bestXTarget { activeGuides.append(SmartGuideLine(orientation: .vertical, position: x)) }
            }
            if bestYDistance <= threshold {
                bestOffset.height += bestYDelta
                if let y = bestYTarget { activeGuides.append(SmartGuideLine(orientation: .horizontal, position: y)) }
            }
        }

        // Clamp within the canvas bounds to avoid dragging tiles off-screen.
        let clampedWidth = min(max(bestOffset.width, 0), max(0, canvasSize.width - currentSize.width))
        let clampedHeight = min(max(bestOffset.height, 0), max(0, canvasSize.height - currentSize.height))

        return (CGSize(width: clampedWidth, height: clampedHeight), activeGuides)
    }
}
