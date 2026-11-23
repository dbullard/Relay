//
//  DashboardTileArrangeOperations.swift
//  Relay
//
//  Align to Grid and Resolve Overlaps as pure functions, so the tile context menu and
//  the Edit ▸ Arrange menu run the same code.
//

import Foundation
import CoreGraphics

enum DashboardTileArrangeOperations {
    /// Moves each selected tile's origin to the nearest grid intersection.
    /// Returns `nil` when `gridSize` isn't positive.
    static func alignedToGrid(
        _ tiles: [DashboardTileModel],
        selectedIDs: Set<UUID>,
        gridSize: CGFloat
    ) -> [DashboardTileModel]? {
        guard gridSize > 0 else { return nil }

        var result = tiles
        for idx in result.indices where selectedIDs.contains(result[idx].id) {
            result[idx].offset.width = (result[idx].offset.width / gridSize).rounded() * gridSize
            result[idx].offset.height = (result[idx].offset.height / gridSize).rounded() * gridSize
        }
        return result
    }

    /// Moves tiles to the nearest free grid position inside the canvas so they don't overlap.
    /// With a selection only the selected (visible) tiles move; otherwise every visible
    /// tile is considered. Hidden tiles are ignored.
    ///
    /// Returns `nil` when `gridSize` isn't positive or there are no visible tiles.
    static func overlapsResolved(
        _ tiles: [DashboardTileModel],
        selectedIDs: Set<UUID>,
        gridSize: CGFloat,
        canvasSize: CGSize,
        defaultTileSize: CGSize
    ) -> (tiles: [DashboardTileModel], didChange: Bool)? {
        guard gridSize > 0 else { return nil }

        var result = tiles
        let visibleTiles = result.filter { !$0.isHidden }
        guard !visibleTiles.isEmpty else { return nil }

        let targetIDs: Set<UUID> = selectedIDs.isEmpty
            ? Set(visibleTiles.map(\.id))
            : selectedIDs

        guard !targetIDs.isEmpty else { return nil }

        func rectFor(tile: DashboardTileModel, offset: CGSize? = nil) -> CGRect {
            let size = DashboardTileSnappingHelper.effectiveSize(for: tile, defaultTileSize: defaultTileSize)
            let origin = offset ?? tile.offset
            return CGRect(x: origin.width, y: origin.height, width: size.width, height: size.height)
        }

        var occupiedRects: [CGRect] = []
        for tile in result where !tile.isHidden && !targetIDs.contains(tile.id) {
            occupiedRects.append(rectFor(tile: tile))
        }

        let canvasWidth = canvasSize.width > 0 ? canvasSize.width : 1200
        let canvasHeight = canvasSize.height > 0 ? canvasSize.height : 800
        let maxRadius = Int(ceil(max(canvasWidth, canvasHeight) / gridSize)) + 2

        func findNearestFreeOffset(baseOffset: CGSize, size: CGSize) -> CGSize {
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

        var didChange = false

        for index in result.indices {
            var tile = result[index]
            guard !tile.isHidden, targetIDs.contains(tile.id) else { continue }

            let size = DashboardTileSnappingHelper.effectiveSize(for: tile, defaultTileSize: defaultTileSize)
            let newOffset = findNearestFreeOffset(baseOffset: tile.offset, size: size)

            if newOffset != tile.offset {
                didChange = true
                tile.offset = newOffset
                result[index] = tile
            }

            occupiedRects.append(rectFor(tile: tile, offset: newOffset))
        }

        return (result, didChange)
    }
}
