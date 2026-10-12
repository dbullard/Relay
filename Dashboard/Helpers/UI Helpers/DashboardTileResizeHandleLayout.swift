import SwiftUI

struct DashboardTileResizeHandleLayout {
    static let hitHalo: CGFloat = 14

    let bottomRight: CGPoint
    let topRight: CGPoint
    let topLeft: CGPoint
    let leftEdge: CGPoint
    let bottomLeft: CGPoint
    let rightEdge: CGPoint
    let bottomEdge: CGPoint
    let topEdge: CGPoint

    init(size: CGSize) {
        bottomRight = CGPoint(x: max(1, size.width - 5), y: max(1, size.height - 5))
        topRight = CGPoint(x: max(1, size.width - 5), y: 5)
        topLeft = CGPoint(x: 5, y: 5)
        leftEdge = CGPoint(x: 1, y: size.height / 2)
        bottomLeft = CGPoint(x: 5, y: max(1, size.height - 5))
        rightEdge = CGPoint(x: max(1, size.width - 1), y: size.height / 2)
        bottomEdge = CGPoint(x: size.width / 2, y: max(1, size.height - 1))
        topEdge = CGPoint(x: size.width / 2, y: 1)
    }

    /// A single resize handle's orientation and canvas-space center point.
    struct Handle {
        let orientation: ResizeHandleOrientation
        let center: CGPoint
    }

    /// All 8 handles for this layout, in a stable order.
    var allHandles: [Handle] {
        [
            Handle(orientation: .diagonal, center: bottomRight),
            Handle(orientation: .diagonalTopRight, center: topRight),
            Handle(orientation: .diagonalTopLeft, center: topLeft),
            Handle(orientation: .horizontalLeft, center: leftEdge),
            Handle(orientation: .diagonalBottomLeft, center: bottomLeft),
            Handle(orientation: .horizontal, center: rightEdge),
            Handle(orientation: .vertical, center: bottomEdge),
            Handle(orientation: .verticalTop, center: topEdge)
        ]
    }

    /// Returns the handle whose center is closest to `point`, provided that
    /// distance is within `hitRadius`. When `allowedOrientations` is
    /// non-nil, only handles with an orientation in that set are considered.
    /// Returns `nil` if no eligible handle is within range.
    func closestHandle(
        to point: CGPoint,
        within hitRadius: CGFloat = DashboardTileResizeHandleLayout.hitHalo,
        allowedOrientations: Set<ResizeHandleOrientation>? = nil
    ) -> Handle? {
        var best: Handle?
        var bestDistance = hitRadius

        for handle in allHandles {
            if let allowedOrientations, !allowedOrientations.contains(handle.orientation) {
                continue
            }
            let distance = hypot(point.x - handle.center.x, point.y - handle.center.y)
            if distance <= bestDistance {
                bestDistance = distance
                best = handle
            }
        }

        return best
    }
}
