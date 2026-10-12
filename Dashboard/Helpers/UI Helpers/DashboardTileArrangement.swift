import Foundation
import CoreGraphics

/// A named fractional region of the canvas that a single tile can be sized and
/// repositioned to fill exactly (half/third/quarter — mirrors macOS's window-tiling
/// menu). Used by the selection action toolbar's "Size" picker.
enum CanvasFractionRegion: String, CaseIterable, Identifiable {
    case halfLeft, halfRight, halfTop, halfBottom
    case thirdLeft, thirdCenter, thirdRight
    case fourthColumn1, fourthColumn2, fourthColumn3, fourthColumn4
    case quarterTopLeft, quarterTopRight, quarterBottomLeft, quarterBottomRight
    case full

    var id: String { rawValue }

    /// The exact rect this region occupies within a canvas of the given size.
    func rect(in canvasSize: CGSize) -> CGRect {
        let w = canvasSize.width
        let h = canvasSize.height
        switch self {
        case .halfLeft:
            return CGRect(x: 0, y: 0, width: w / 2, height: h)
        case .halfRight:
            return CGRect(x: w / 2, y: 0, width: w / 2, height: h)
        case .halfTop:
            return CGRect(x: 0, y: 0, width: w, height: h / 2)
        case .halfBottom:
            return CGRect(x: 0, y: h / 2, width: w, height: h / 2)
        case .thirdLeft:
            return CGRect(x: 0, y: 0, width: w / 3, height: h)
        case .thirdCenter:
            return CGRect(x: w / 3, y: 0, width: w / 3, height: h)
        case .thirdRight:
            return CGRect(x: 2 * w / 3, y: 0, width: w / 3, height: h)
        case .fourthColumn1:
            return CGRect(x: 0, y: 0, width: w / 4, height: h)
        case .fourthColumn2:
            return CGRect(x: w / 4, y: 0, width: w / 4, height: h)
        case .fourthColumn3:
            return CGRect(x: 2 * w / 4, y: 0, width: w / 4, height: h)
        case .fourthColumn4:
            return CGRect(x: 3 * w / 4, y: 0, width: w / 4, height: h)
        case .quarterTopLeft:
            return CGRect(x: 0, y: 0, width: w / 2, height: h / 2)
        case .quarterTopRight:
            return CGRect(x: w / 2, y: 0, width: w / 2, height: h / 2)
        case .quarterBottomLeft:
            return CGRect(x: 0, y: h / 2, width: w / 2, height: h / 2)
        case .quarterBottomRight:
            return CGRect(x: w / 2, y: h / 2, width: w / 2, height: h / 2)
        case .full:
            return CGRect(x: 0, y: 0, width: w, height: h)
        }
    }

    /// Human-readable label used as a tooltip / accessibility label in the picker.
    var label: String {
        switch self {
        case .halfLeft: return "Left Half"
        case .halfRight: return "Right Half"
        case .halfTop: return "Top Half"
        case .halfBottom: return "Bottom Half"
        case .thirdLeft: return "Left Third"
        case .thirdCenter: return "Center Third"
        case .thirdRight: return "Right Third"
        case .fourthColumn1: return "Column 1"
        case .fourthColumn2: return "Column 2"
        case .fourthColumn3: return "Column 3"
        case .fourthColumn4: return "Column 4"
        case .quarterTopLeft: return "Top Left"
        case .quarterTopRight: return "Top Right"
        case .quarterBottomLeft: return "Bottom Left"
        case .quarterBottomRight: return "Bottom Right"
        case .full: return "Full Canvas"
        }
    }

    /// Groups regions for the picker's sectioned layout.
    var section: String {
        switch self {
        case .halfLeft, .halfRight, .halfTop, .halfBottom:
            return "Half"
        case .thirdLeft, .thirdCenter, .thirdRight:
            return "Thirds"
        case .fourthColumn1, .fourthColumn2, .fourthColumn3, .fourthColumn4:
            return "Fourths"
        case .quarterTopLeft, .quarterTopRight, .quarterBottomLeft, .quarterBottomRight:
            return "Quarters"
        case .full:
            return "Full"
        }
    }

    /// Given a drag point in canvas coordinates, returns the region it's
    /// proximate to (within `edgeThreshold` of an edge/corner), or nil for
    /// the open middle of the canvas. All four corners resolve to quarters,
    /// checked before the top-edge case -- so `.full` only wins in the
    /// center portion of the top edge, not the corners, matching macOS's
    /// own quarter-tiling corners plus a separate top-edge maximize zone.
    static func proximityRegion(
        at point: CGPoint,
        canvasSize: CGSize,
        edgeThreshold: CGFloat
    ) -> CanvasFractionRegion? {
        let nearTop = point.y <= edgeThreshold
        let nearBottom = point.y >= canvasSize.height - edgeThreshold
        let nearLeft = point.x <= edgeThreshold
        let nearRight = point.x >= canvasSize.width - edgeThreshold

        if nearTop && nearLeft { return .quarterTopLeft }
        if nearTop && nearRight { return .quarterTopRight }
        if nearBottom && nearLeft { return .quarterBottomLeft }
        if nearBottom && nearRight { return .quarterBottomRight }
        if nearTop { return .full }
        if nearLeft { return .halfLeft }
        if nearRight { return .halfRight }
        if nearBottom { return .halfBottom }
        return nil
    }
}

enum DistributeAxis {
    case horizontal, vertical
}

/// Just enough of a tile's geometry to compute a distribute pass, decoupled from
/// `DashboardTileModel` so this logic has no SwiftUI/view dependencies.
struct DistributableTile {
    let id: UUID
    let offset: CGSize
}

enum TileDistribution {
    /// A grid shape: how many equal-width columns and equal-height rows a
    /// selection is split into. For horizontal distribution this is filled
    /// row-major (left-to-right, then top-to-bottom); for vertical,
    /// column-major (top-to-bottom, then left-to-right).
    struct GridShape: Equatable {
        let columns: Int
        let rows: Int
    }

    /// The grid shape for a selection of `count` tiles on `axis`, ignoring
    /// canvas size / minimum pane size (see `fittingShape` for the
    /// size-aware search `distribute` actually uses).
    ///
    /// `count <= 4` always returns a single strip (`columns: count, rows: 1`
    /// for horizontal; the transpose for vertical) — this matches
    /// `distribute`'s pre-grid behavior exactly, so 3-4 tile selections
    /// don't change. `count >= 5` returns a near-square split, biased wide
    /// for horizontal / tall for vertical: starting from `primary =
    /// ceil(sqrt(count))`, grow the biased dimension until it's >= the
    /// other. This always yields at least 2 rows (horizontal) or 2 columns
    /// (vertical) once `count >= 5`, since `ceil(sqrt(count))` grows
    /// strictly slower than `count` — so the single-strip/grid split above
    /// is the only place a strip can occur.
    static func idealShape(count: Int, axis: DistributeAxis) -> GridShape {
        guard count > 0 else { return GridShape(columns: 0, rows: 0) }

        if count <= 4 {
            switch axis {
            case .horizontal: return GridShape(columns: count, rows: 1)
            case .vertical: return GridShape(columns: 1, rows: count)
            }
        }

        let primary = Int(ceil(sqrt(Double(count))))
        switch axis {
        case .horizontal:
            var columns = primary
            var rows = Int(ceil(Double(count) / Double(columns)))
            while rows > columns {
                columns += 1
                rows = Int(ceil(Double(count) / Double(columns)))
            }
            return GridShape(columns: columns, rows: rows)
        case .vertical:
            var rows = primary
            var columns = Int(ceil(Double(count) / Double(rows)))
            while columns > rows {
                rows += 1
                columns = Int(ceil(Double(count) / Double(rows)))
            }
            return GridShape(columns: columns, rows: rows)
        }
    }

    /// `idealShape`, adjusted so every pane meets `DashboardTileMetrics`'s
    /// minimum tile size for `canvasSize`. If the ideal shape's panes are
    /// already big enough, returns it unchanged. Otherwise searches every
    /// other valid shape (one per possible `columns` value from 1 to
    /// `count`) for the one closest to the ideal shape's squareness whose
    /// panes still meet the minimum, tie-broken by the same axis bias as
    /// `idealShape`. Returns `nil` if no shape's panes meet the minimum.
    static func fittingShape(count: Int, axis: DistributeAxis, canvasSize: CGSize) -> GridShape? {
        guard count > 0, canvasSize.width > 0, canvasSize.height > 0 else { return nil }

        func paneFits(_ shape: GridShape) -> Bool {
            let paneWidth = canvasSize.width / CGFloat(shape.columns)
            let paneHeight = canvasSize.height / CGFloat(shape.rows)
            return paneWidth >= DashboardTileMetrics.minWidth && paneHeight >= DashboardTileMetrics.minHeight
        }

        let ideal = idealShape(count: count, axis: axis)
        if paneFits(ideal) { return ideal }

        // NOTE: candidates are always parameterized as (columns, rows: ceil(count/columns)),
        // which is axis-correct for horizontal but not the "true" axis-aware parameterization
        // for vertical (where rows should be the primary/driving dimension). This is currently
        // harmless because the squareness + bias tie-break below dominates and lands on the
        // same answer either way — but that's an emergent property of the tie-break, not a
        // structural guarantee. If the tie-break logic changes, re-verify vertical correctness
        // (see testDistributeVerticallyStretchesThePartialLastColumnToFillTheCanvas).
        let candidates = (1...count).map { columns in
            GridShape(columns: columns, rows: Int(ceil(Double(count) / Double(columns))))
        }
        let fitting = candidates.filter(paneFits)
        guard !fitting.isEmpty else { return nil }

        func squareness(_ shape: GridShape) -> Int { abs(shape.columns - shape.rows) }
        func matchesBias(_ shape: GridShape) -> Bool {
            axis == .horizontal ? shape.columns >= shape.rows : shape.rows >= shape.columns
        }

        return fitting.min { lhs, rhs in
            let lhsSquareness = squareness(lhs)
            let rhsSquareness = squareness(rhs)
            if lhsSquareness != rhsSquareness { return lhsSquareness < rhsSquareness }
            let lhsBias = matchesBias(lhs)
            let rhsBias = matchesBias(rhs)
            if lhsBias != rhsBias { return lhsBias && !rhsBias }
            return lhs.columns < rhs.columns
        }
    }

    /// Whether `distribute` would succeed for `count` tiles on `axis` given
    /// `canvasSize` — i.e. whether any grid shape's panes meet the minimum
    /// tile size. Used to disable the toolbar's distribute buttons instead
    /// of letting them silently no-op.
    static func canDistribute(count: Int, axis: DistributeAxis, canvasSize: CGSize) -> Bool {
        guard count >= 2 else { return false }
        return fittingShape(count: count, axis: axis, canvasSize: canvasSize) != nil
    }

    /// Divides `canvasSize` into a grid of equal panes and resizes/repositions
    /// every tile in `tiles` to exactly fill one pane, edge-to-edge, with no
    /// gaps or overlap. For 2-4 tiles this is a single row (horizontal) or
    /// column (vertical), matching the pre-grid behavior; for 5+ tiles it's
    /// a near-square grid (see `idealShape`). If the grid's cell count
    /// doesn't evenly divide `tiles.count`, the final row (horizontal) or
    /// column (vertical) has its tiles stretched to still span the full
    /// canvas extent rather than leaving a gap.
    ///
    /// Tiles are assigned to panes in reading order for the grid — row-major
    /// (by `offset.height` then `offset.width`) for horizontal, column-major
    /// (by `offset.width` then `offset.height`) for vertical — so a
    /// left-to-right/top-to-bottom arrangement is preserved.
    ///
    /// Returns an empty dictionary if fewer than 2 tiles are given, if
    /// `canvasSize` has zero width/height, or if no grid shape's panes would
    /// meet the minimum tile size — in which case distributing would just
    /// produce overlapping tiles.
    static func distribute(
        tiles: [DistributableTile],
        axis: DistributeAxis,
        canvasSize: CGSize
    ) -> [UUID: CGRect] {
        guard tiles.count >= 2, canvasSize.width > 0, canvasSize.height > 0 else { return [:] }
        guard let shape = fittingShape(count: tiles.count, axis: axis, canvasSize: canvasSize) else { return [:] }

        let sorted: [DistributableTile]
        switch axis {
        case .horizontal:
            sorted = tiles.sorted {
                if $0.offset.height != $1.offset.height { return $0.offset.height < $1.offset.height }
                return $0.offset.width < $1.offset.width
            }
        case .vertical:
            sorted = tiles.sorted {
                if $0.offset.width != $1.offset.width { return $0.offset.width < $1.offset.width }
                return $0.offset.height < $1.offset.height
            }
        }

        let primaryCount = axis == .horizontal ? shape.columns : shape.rows
        let secondaryCount = axis == .horizontal ? shape.rows : shape.columns
        let secondaryLength = (axis == .horizontal ? canvasSize.height : canvasSize.width) / CGFloat(secondaryCount)

        var result: [UUID: CGRect] = [:]
        for (index, tile) in sorted.enumerated() {
            let line = index / primaryCount
            let positionInLine = index % primaryCount
            let tilesInThisLine = min(primaryCount, sorted.count - line * primaryCount)
            let primaryLength = (axis == .horizontal ? canvasSize.width : canvasSize.height) / CGFloat(tilesInThisLine)

            let primaryOrigin = CGFloat(positionInLine) * primaryLength
            let secondaryOrigin = CGFloat(line) * secondaryLength

            switch axis {
            case .horizontal:
                result[tile.id] = CGRect(x: primaryOrigin, y: secondaryOrigin, width: primaryLength, height: secondaryLength)
            case .vertical:
                result[tile.id] = CGRect(x: secondaryOrigin, y: primaryOrigin, width: secondaryLength, height: primaryLength)
            }
        }
        return result
    }

    /// `distribute(tiles:axis:canvasSize:)`, scoped to an arbitrary target
    /// rect instead of the whole canvas, with the axis inferred from the
    /// rect's own aspect ratio (wider-than-tall -> horizontal, taller-than-wide
    /// -> vertical) rather than passed explicitly -- used by option-drag
    /// snapping, where there's no separate axis picker mid-gesture. Returns
    /// nil if the region is too small to give every tile the minimum tile
    /// size (the same condition `distribute` itself returns an empty
    /// dictionary for), or if `regionRect` has zero width/height.
    static func distribute(tiles: [DistributableTile], into regionRect: CGRect) -> [UUID: CGRect]? {
        guard regionRect.width > 0, regionRect.height > 0 else { return nil }

        let axis: DistributeAxis = regionRect.width >= regionRect.height ? .horizontal : .vertical
        let localFrames = distribute(tiles: tiles, axis: axis, canvasSize: regionRect.size)
        guard !localFrames.isEmpty else { return nil }

        return localFrames.mapValues { $0.offsetBy(dx: regionRect.minX, dy: regionRect.minY) }
    }

    /// Whether an option-drag-snap (or the "Distribute" toolbar buttons)
    /// should treat `anchorID` as part of a multi-tile group rather than
    /// snapping/distributing it alone -- shared by the live preview
    /// (`DashboardTileContainer`) and the commit
    /// (`DashboardRootView.applySnapRegion`) so the two can never disagree
    /// about which tiles move.
    static func isMultiTileSelection(anchorID: UUID, selectedTileIDs: Set<UUID>) -> Bool {
        selectedTileIDs.contains(anchorID) && selectedTileIDs.count > 1
    }
}

/// Decides whether the selection action toolbar should render above or below the
/// current selection, so it never clips off the top of the visible viewport.
enum SelectionToolbarPlacement {
    /// Default local-space height budgeted for the toolbar's chrome, and the
    /// margin kept between it and the selection. Shared with
    /// `SelectionActionToolbarView`, which anchors itself at
    /// `defaultToolbarLocalHeight / 2 + defaultLocalMargin` above/below the
    /// selection — keeping both in one place so they can't silently drift apart.
    static let defaultToolbarLocalHeight: CGFloat = 40
    static let defaultLocalMargin: CGFloat = 20
    static let defaultAnchorOffset: CGFloat = defaultToolbarLocalHeight / 2 + defaultLocalMargin

    static func shouldFlipBelow(
        selectionRect: CGRect,
        viewportZoom: CGFloat,
        viewportPanY: CGFloat,
        toolbarLocalHeight: CGFloat = defaultToolbarLocalHeight,
        localMargin: CGFloat = defaultLocalMargin
    ) -> Bool {
        let zoom = max(0.0001, viewportZoom)
        let anchorY = selectionRect.minY - toolbarLocalHeight - localMargin
        let screenY = (anchorY * zoom) + viewportPanY
        return screenY < 0
    }
}
