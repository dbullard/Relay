import CoreGraphics

/// Geometry for the VoiceOver "Move …" and "Resize …" tile actions.
enum DashboardTileAccessibilityAdjustment {
    enum Move: CaseIterable {
        case left, right, up, down

        var actionName: String {
            switch self {
            case .left: return "Move Left"
            case .right: return "Move Right"
            case .up: return "Move Up"
            case .down: return "Move Down"
            }
        }
    }

    enum Resize: CaseIterable {
        case wider, narrower, taller, shorter

        var actionName: String {
            switch self {
            case .wider: return "Make Wider"
            case .narrower: return "Make Narrower"
            case .taller: return "Make Taller"
            case .shorter: return "Make Shorter"
            }
        }
    }

    /// One grid cell when Snap to Grid is on, otherwise 10 points.
    static func step(snapToGrid: Bool, gridSize: CGFloat) -> CGFloat {
        (snapToGrid && gridSize > 0) ? gridSize : 10
    }

    static func translation(for move: Move, step: CGFloat) -> CGSize {
        switch move {
        case .left: return CGSize(width: -step, height: 0)
        case .right: return CGSize(width: step, height: 0)
        case .up: return CGSize(width: 0, height: -step)
        case .down: return CGSize(width: 0, height: step)
        }
    }

    /// The new size, never below the tile minimums.
    static func resized(
        _ size: CGSize,
        by resize: Resize,
        step: CGFloat,
        minimum: CGSize = CGSize(width: DashboardTileMetrics.minWidth, height: DashboardTileMetrics.minHeight)
    ) -> CGSize {
        var result = size
        switch resize {
        case .wider: result.width += step
        case .narrower: result.width -= step
        case .taller: result.height += step
        case .shorter: result.height -= step
        }
        result.width = max(minimum.width, result.width)
        result.height = max(minimum.height, result.height)
        return result
    }

    /// True when any of `rects` overlaps any of `obstacles`.
    static func overlaps(_ rects: [CGRect], obstacles: [CGRect]) -> Bool {
        rects.contains { rect in obstacles.contains { $0.intersects(rect) } }
    }
}
